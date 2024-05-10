ARG GO_VERSION=1.20

FROM golang:$GO_VERSION-alpine3.18
ENV CGO_ENABLED=0
RUN \
  apk add --no-cache jq && \
  wget https://github.com/jstemmer/go-junit-report/releases/download/v2.0.0/go-junit-report-v2.0.0-linux-amd64.tar.gz -O - | \
  tar -xzvf - -C $GOPATH/bin && \
  wget https://github.com/golangci/golangci-lint/releases/download/v1.58.0/golangci-lint-1.58.0-linux-amd64.tar.gz -O - | \
  tar -xzvf - -C $GOPATH/bin --strip-components 1 golangci-lint-1.58.0-linux-amd64/golangci-lint && \
  wget https://github.com/matm/gocov-html/releases/download/v1.4.0/gocov-html-v1.4.0-linux-amd64.zip -O - | unzip - && \
  mv gocov-html/gocov-html $GOPATH/bin && chmod +x $GOPATH/bin/gocov-html && \
  go install github.com/axw/gocov/gocov@v1.1.0 && \
  go install github.com/AlekSi/gocov-xml@v1.1.0 && \
  go install golang.org/x/vuln/cmd/govulncheck@v1.1.0 && \
  go install github.com/google/go-licenses@v1.6.0 && \
  go install github.com/johnstarich/go/gopages@v0.1.25 && \
  rm -r $GOPATH/pkg $(go env GOCACHE)

