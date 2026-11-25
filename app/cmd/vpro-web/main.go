package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/boostao/vpro/app/internal/lifecycle"
)

func main() {
	devSample := flag.Bool("dev-sample", false, "run against an embedded read-only Sample.db snapshot when VPRO_WEB_DATA_DIR is unset")
	showVersion := flag.Bool("version", false, "print build version metadata and exit")
	flag.Parse()

	if *showVersion {
		info := lifecycle.CurrentBuildInfo()
		fmt.Printf("vpro-web %s (%s, commit %s, built %s)\n", info.AppVersion, info.BuildMode, info.GitCommit, info.BuildDate)
		return
	}

	cfg, err := LoadWebConfig(os.LookupEnv, *devSample)
	if err != nil {
		log.Fatalf("vpro-web configuration error: %v", err)
	}

	rootCtx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	srv, err := NewWebServer(rootCtx, cfg)
	if err != nil {
		log.Fatalf("vpro-web startup failed: %v", err)
	}
	defer srv.Close()

	publicHTTP := &http.Server{
		Addr:              cfg.ListenAddr,
		Handler:           srv.PublicHandler(),
		ReadHeaderTimeout: 15 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      cfg.RTimeout + 30*time.Second,
		IdleTimeout:       120 * time.Second,
	}

	internalHTTP := &http.Server{
		Addr:              cfg.InternalAddr,
		Handler:           srv.InternalHandler(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	errCh := make(chan error, 2)
	go func() {
		log.Printf("vpro-web public server listening on %s (env=%s, snapshot=%s, datasets=%d, r=%v)",
			cfg.ListenAddr, cfg.Env, srv.currentSnapshot().Manifest.SnapshotID, len(srv.currentSnapshot().Catalog.Datasets), srv.isRAvailable())
		if err := publicHTTP.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- fmt.Errorf("public server: %w", err)
		}
	}()

	go func() {
		log.Printf("vpro-web internal loopback server listening on %s", cfg.InternalAddr)
		if err := internalHTTP.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- fmt.Errorf("internal server: %w", err)
		}
	}()

	select {
	case <-rootCtx.Done():
		log.Printf("vpro-web shutting down gracefully...")
	case serveErr := <-errCh:
		log.Printf("vpro-web fatal listener error: %v", serveErr)
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	_ = internalHTTP.Shutdown(shutdownCtx)
	_ = publicHTTP.Shutdown(shutdownCtx)
}
