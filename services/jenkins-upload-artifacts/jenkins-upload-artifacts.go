// SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: MIT

// Provides a Webserver forwarding Multipart uploads to WebDAV.
//
// It acts as glue code between the
// [Jenkins HTTP POST plugin](https://plugins.jenkins.io/http-post/) and
// `rclone serve webdav`, which can expose many different storage backends.
//
// The WebDAV endpoint to which to forward to is configurable, as well as the
// rules to apply in determining the desired target path.
//
// The Jenkins Plugin sends three HTTP Headers (Job Name, Build Number and Timestamp).
// These can be used in a template string, passed as `-target-tpl` argument to
// construct the target path.
//
// The service relies on being started through systemd socket activation, or
// picks a random port on http to listen on.
package main

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"mime"
	"mime/multipart"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"path"
	"strconv"
	"strings"
	"text/template"
	"time"
)

func main() {
	// CLI arg parsing
	var targetTplStr string
	var targetURLStr string
	flag.StringVar(&targetURLStr, "target-url", "http://localhost", "URL pointing to the WebDAV endpoint (base), or unix:// path")
	flag.StringVar(&targetTplStr, "target-tpl", "{{.jobName}}/{{.buildNumber}}/{{.buildTimestamp}}/{{.fileName}}", "Template string to construct target path to upload artifacts to, relative to the base URL.")
	flag.Parse()

	// Set up logging
	logger := slog.New(slog.NewTextHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	// Parse the template
	targetTpl := template.New("t1")
	targetTpl = template.Must(targetTpl.Parse(targetTplStr))

	// Handle interrupts
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	// Parse targetURL
	targetURL, err := url.Parse(targetURLStr)
	if err != nil {
		slog.Error("Failed to parse target base url", "targetBaseURL", targetURL, "err", err)
		os.Exit(1)
	}

	// configure HTTP *client*
	httpClient, err := makeHTTPClient(*targetURL)

	// If the targetURL used unix scheme, set Path to empty, and scheme back to HTTP.
	// The HTTP client with custom dialer is already created, we want to speak HTTP inside.
	if targetURL.Scheme == "unix" {
		targetURL.Host = "127.0.0.1" // doesn't matter
		targetURL.Path = ""
		targetURL.Scheme = "http"
	}

	// set up and configure server
	mux := http.NewServeMux()
	mux.HandleFunc("/", makeUploadHandler(logger, targetTpl, *targetURL, httpClient))

	srv := http.Server{
		Handler: mux,
	}

	var l net.Listener
	if os.Getenv("LISTEN_PID") == strconv.Itoa(os.Getpid()) {
		logger.Info("using systemd socket activation")
		f := os.NewFile(3, "from systemd")
		l, err = net.FileListener(f)
	} else {
		l, err = net.Listen("tcp", "")
	}

	if err != nil {
		logger.Error("Failed to listen", "err", err)
		os.Exit(1)
	}

	logger.Info("Starting up server", "listen_address", l.Addr().String())

	go func() {
		if err := srv.Serve(l); err != nil {
			if !errors.Is(err, http.ErrServerClosed) {
				logger.Error("Error from Serve", "err", err)
				stop()
				os.Exit(1)
			}
		}
	}()

	select {
	case <-ctx.Done():
		srv.Close()
	}
}

// constructs a HTTP Client, using an URL to specify protocol,
// (hostname and port) or (path).
func makeHTTPClient(url url.URL) (*http.Client, error) {
	var dialContext func(context.Context, string, string) (net.Conn, error)
	if url.Scheme == "http" || url.Scheme == "https" {
		dialContext = func(ctx context.Context, network, addr string) (net.Conn, error) {
			return net.Dial("tcp", url.Host)
		}
	} else if url.Scheme == "unix" {
		dialContext = func(ctx context.Context, network, addr string) (net.Conn, error) {
			return net.Dial("unix", url.Path)
		}
	} else {
		return nil, fmt.Errorf("unrecognized url scheme: %v", url.Scheme)
	}

	return &http.Client{
		Transport: &http.Transport{
			DialContext: dialContext,
		},
	}, nil
}

// Parses HTTP Headers into jobName, buildNumber, and buildTimestamp, or an error.
func parseHeaders(rq *http.Request) (string, string, string, error) {
	// parse request headers
	jobName := rq.Header.Get("Job-Name")                     // build.getProject().getName()
	buildNumber := rq.Header.Get("Build-Number")             // build.getNumber()
	buildTimestampMillis := rq.Header.Get("Build-Timestamp") // build.getTimeInMillis(), which is milliseconds since epoch

	if jobName == "" || buildNumber == "" || buildTimestampMillis == "" {
		return "", "", "", fmt.Errorf("missing headers")
	}

	// parse buildTimestamp to a human-readable string.
	i, err := strconv.ParseInt(buildTimestampMillis, 10, 64)
	if err != nil {
		return "", "", "", fmt.Errorf("unable to parse build timestamp: %w", err)

	}
	buildTimestamp := time.UnixMilli(i).UTC().Format(time.RFC3339)

	return jobName, buildNumber, buildTimestamp, nil
}

// Creates all directories leading to a given path, by issuing a MKCOL HTTP request.
func mkdirAll(ctx context.Context, httpClient *http.Client, url url.URL) error {
	targetPathParents := []string{}

	{
		rest := url.Path
		for {
			rst, f := path.Split(rest)
			targetPathParents = append(targetPathParents, rst)

			rest = path.Clean(rst)

			if rst == "" && f == "." {
				break
			}
		}
	}

	for i := len(targetPathParents) - 1; i >= 0; i-- {
		u := url
		u.Path = targetPathParents[i]

		rq, err :=
			http.NewRequestWithContext(ctx, "MKCOL", u.String(), nil)

		if err != nil {
			return fmt.Errorf("failed to construct MKCOL request: %w", err)
		}

		resp, err := httpClient.Do(rq)
		if err != nil {
			return fmt.Errorf("unable to create intermediate dir %v: %w", u.Path, err)
		}

		if statusOK := resp.StatusCode >= 200 && resp.StatusCode < 300; !statusOK {
			return fmt.Errorf("unsuccessful intermediate dir creation, status code %d", resp.StatusCode)
		}
	}

	return nil
}

// Uploads an individual file to the supplied URL, failing if something already exists there.
func uploadPart(ctx context.Context, httpClient *http.Client, url string, r io.Reader) error {
	// Do a HEAD request to check if the file already exists and bail out if so.
	rq, err := http.NewRequestWithContext(ctx, "HEAD", url, nil)
	if err != nil {
		return fmt.Errorf("unable to construct http HEAD request: %w", err)
	}

	resp, err := httpClient.Do(rq)
	if err != nil {
		return fmt.Errorf("unable to do HEAD request: %w", err)
	}

	// The only status code we accept is a 404 - the file should not exist yet.
	if resp.StatusCode != http.StatusNotFound {
		// File already exists, bail out.
		return fmt.Errorf("file already exists, or other error, bailing out")
	}

	// Construct and do the PUT request to upload the file.
	rq, err = http.NewRequestWithContext(ctx, "PUT", url, bufio.NewReaderSize(r, 9000))
	if err != nil {
		return fmt.Errorf("unable to construct http PUT request: %w", err)
	}

	resp, err = httpClient.Do(rq)
	if err != nil {
		return fmt.Errorf("unable to do PUT request: %w", err)
	}

	if statusOK := resp.StatusCode >= 200 && resp.StatusCode < 300; !statusOK {
		return fmt.Errorf("unsuccessful upload, status code %d", resp.StatusCode)
	}
	return nil
}

func makeUploadHandler(logger *slog.Logger, targetTpl *template.Template, targetURLBase url.URL, httpClient *http.Client) func(http.ResponseWriter, *http.Request) {
	return func(w http.ResponseWriter, rq *http.Request) {
		if rq.Method != "POST" {
			w.WriteHeader(http.StatusBadRequest)
			return
		}

		defer rq.Body.Close()

		// Parse HTTP headers
		jobName, buildNumber, buildTimestamp, err := parseHeaders(rq)
		if err != nil {
			slog.Warn("unable to parse headers", "err", err)
			w.WriteHeader(http.StatusBadRequest)
			return
		}

		logger = logger.With(slog.String("jobName", jobName), slog.String("buildNumber", buildNumber), slog.String("buildTimestamp", buildTimestamp))

		// The request is a multipart form upload.
		mediaType, params, err := mime.ParseMediaType(rq.Header.Get("Content-Type"))
		if err != nil {
			logger.Warn("unable to parse media type", "err", err)
			w.WriteHeader(http.StatusBadRequest)
		}

		if !strings.HasPrefix(mediaType, "multipart/") {
			logger.Warn("no multipart request", "err", err)
			w.WriteHeader(http.StatusBadRequest)

		}

		mr := multipart.NewReader(rq.Body, params["boundary"])

		for {
			p, err := mr.NextPart()
			if errors.Is(err, io.EOF) {
				break
			}
			if err != nil {
				logger.Warn("failed getting next part", "err", err)
				w.WriteHeader(http.StatusBadRequest)
			}
			defer p.Close()

			// clean filename
			fileName := path.Clean(p.FileName())

			logger := logger.With(slog.String("fileName", fileName))

			if fileName == "" || strings.HasPrefix(fileName, ".") || strings.HasPrefix(fileName, "..") {
				logger.Warn("got empty or invalid FileName, skipping")
				continue
			}

			// Calculate target path
			buf := &bytes.Buffer{}
			targetTpl.Execute(buf, map[string]string{
				"jobName":        jobName,
				"buildNumber":    buildNumber,
				"buildTimestamp": buildTimestamp,
				"fileName":       p.FileName(),
			})

			// Append the fileName to the base URL
			targetURL := targetURLBase.JoinPath(buf.String())
			logger = logger.With(slog.String("targetURL", targetURL.String()))

			logger.Info("creating intermediate dirs")

			// create intermediate dirs if necessary.
			if err := mkdirAll(rq.Context(), httpClient, *targetURL); err != nil {
				logger.Warn("unable to create intermediate dirs", "err", err)
				w.WriteHeader(http.StatusInternalServerError)
				return
			}

			// Construct and do a HTTP PUT request, using p (the multipart content) as body.
			rd := bufio.NewReaderSize(p, 4096*8)
			if err := uploadPart(rq.Context(), httpClient, targetURL.String(), rd); err != nil {
				logger.Warn("unable to upload part")
				w.WriteHeader(http.StatusInternalServerError)
				return
			} else {
				slog.Info("successfully uploaded artifact")
			}
		}
	}
}
