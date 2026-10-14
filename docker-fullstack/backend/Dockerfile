# Этап сборки: компилятор Go нужен только здесь.
# В финальный образ он не попадает — иначе образ был бы сотни мегабайт.
FROM golang:1.22-alpine AS builder

WORKDIR /build

# Сначала зависимости. Пока меняются только .go-файлы, этот слой берётся из кэша:
# Docker сравнивает точную последовательность инструкций и не качает модули заново.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
# CGO выключен, чтобы бинарник не зависел от glibc: distroless/static его не содержит.
# -ldflags="-s -w" убирает отладочную информацию, образ получается меньше.
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/app ./main.go

# Этап исполнения: нет shell, нет пакетного менеджера, процесс не от root.
# Даже если процесс скомпрометируют, запустить sh внутри контейнера нельзя.
FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /app
COPY --from=builder /out/app /app/app

EXPOSE 8080
# ENTRYPOINT фиксирует бинарник, аргументы при необходимости можно передать в CMD.
ENTRYPOINT ["/app/app"]
