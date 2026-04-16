FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-s -w" -o /out/sshido-relay .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/sshido-relay /usr/local/bin/sshido-relay
EXPOSE 8080
ENV ADDR=0.0.0.0:8080 STORAGE=firestore
ENTRYPOINT ["/usr/local/bin/sshido-relay"]
