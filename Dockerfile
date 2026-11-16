# AWS S3 Proxy
# docker run -d -p 8080:80 -e AWS_REGION -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_S3_BUCKET patrickdk/s3-proxy

FROM --platform=$BUILDPLATFORM golang:alpine AS builder
COPY .gitignore /usr/bin/
RUN apk --no-cache add gcc musl-dev git
WORKDIR /go/src/
COPY go.mod go.sum ./
ENV GOCACHE=/go-cache
ENV GOMODCACHE=/gomod-cache
RUN --mount=type=cache,target=/gomod-cache \
    export GOPROXY=direct \
    && go mod download \
    && go mod verify
COPY . ./
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG BUILD_VERSION
ARG BUILD_DATE
ARG BUILD_REF
RUN --mount=type=cache,target=/gomod-cache \
    --mount=type=cache,target=/go-cache \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 \
    go build \
    -ldflags "-s -w -X main.ver=${BUILD_VERSION} \
    -X main.commit=${BUILD_REF} \
    -X main.date=${BUILD_DATE}" -o /health ./healthcheck \
 && GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 \
    go build \
    -ldflags "-s -w -X main.ver=${BUILD_VERSION} \
    -X main.commit=${BUILD_REF} \
    -X main.date=${BUILD_DATE}" -o /app

FROM alpine AS libs
RUN apk --no-cache add ca-certificates

FROM scratch AS base
COPY --from=libs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /health /health
COPY --from=builder /app /aws-s3-proxy
ENTRYPOINT ["/aws-s3-proxy"]
HEALTHCHECK --interval=5s --timeout=1s --start-period=5s --retries=3 CMD [ "/health" ]

FROM base AS dist-lambda
COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:1.1.0 /lambda-adapter /opt/extensions/lambda-adapter

FROM base AS dist
