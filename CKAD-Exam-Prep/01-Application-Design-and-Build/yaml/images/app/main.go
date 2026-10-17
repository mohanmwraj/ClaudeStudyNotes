// Tiny HTTP server used by ../Dockerfile.multistage.
//
//	GET /        -> message, version and hostname
//	GET /healthz -> "ok" (use it for liveness/readiness probes)
//
// APP_MESSAGE (env) changes the message; -port changes the listen port.
package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
)

// version is overwritten at build time: go build -ldflags "-X main.version=1.2.0"
var version = "dev"

func main() {
	port := flag.String("port", "8080", "port to listen on")
	flag.Parse()

	msg := os.Getenv("APP_MESSAGE")
	if msg == "" {
		msg = "hello from the CKAD study kit"
	}
	host, _ := os.Hostname()

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "%s (version=%s, host=%s)\n", msg, version, host)
	})
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "ok")
	})

	log.Printf("listening on :%s (version %s)", *port, version)
	log.Fatal(http.ListenAndServe(":"+*port, nil))
}
