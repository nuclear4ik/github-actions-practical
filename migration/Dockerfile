FROM golang:1.22-bookworm
ARG MIGRATION_ASSIST_COMMIT=2544853a57206ed2561a8d279f68388dbf002205
ENV GOMAXPROCS=2
RUN go install github.com/mattermost/migration-assist/cmd/migration-assist@${MIGRATION_ASSIST_COMMIT}
WORKDIR /work
ENTRYPOINT ["migration-assist"]
