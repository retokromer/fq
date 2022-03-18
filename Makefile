GO_BUILD_FLAGS ?= -trimpath
GO_BUILD_LDFLAGS ?= -s -w
GO_TEST_RACE_FLAGS ?=-race

all: test fq

.PHONY: fq
fq:
	CGO_ENABLED=0 go build -o fq -ldflags "${GO_BUILD_LDFLAGS}" ${GO_BUILD_FLAGS} .

.PHONY: test
test: testgo testjq testcli

.PHONY: testgo
# figure out all go pakges with test files
testgo: PKGS=$(shell find . -name "*_test.go" | xargs -n 1 dirname | sort | uniq)
testgo:
	go test ${GO_TEST_RACE_FLAGS} ${VERBOSE} ${COVER} ${PKGS}

.PHONY: testjq
testjq: fq
	@pkg/interp/testjq.sh ./fq pkg/interp/*_test.jq

.PHONY: testcli
testcli: fq
	@pkg/cli/test_exp.sh ./fq pkg/cli/test_repl.exp
	@pkg/cli/test_exp.sh ./fq pkg/cli/test_cli_ctrlc.exp
	@pkg/cli/test_exp.sh ./fq pkg/cli/test_cli_ctrld.exp

.PHONY: cover
cover: COVER=-cover -coverpkg=./... -coverprofile=cover.out
cover: test
	go tool cover -html=cover.out -o cover.out.html
	cat cover.out.html | grep '<option value="file' | sed -E 's/.*>(.*) \((.*)%\)<.*/\2 \1/' | sort -rn

.PHONY: doc
doc: doc/formats.svg doc/demo.svg
doc: doc/display_json.svg
doc: doc/display_decode_value.svg
doc: doc/display_decode_value_d.svg
doc: doc/display_decode_value_dv.svg
	@doc/mdsh.sh ./fq *.md doc/*.md

doc/%.svg: doc/%.sh fq
	(cd doc ; ../$< ../fq) | go run github.com/wader/ansisvg@master > $@

.PHONY: doc/formats.svg
doc/formats.svg: fq
# ignore graphviz version as it causes diff when nothing has changed
	./fq -rnf doc/formats_diagram.jq | dot -Tsvg | sed 's/Generated by graphviz.*//' > doc/formats.svg

doc/file.mp3: Makefile
	ffmpeg -y -f lavfi -i sine -f lavfi -i testsrc -map 0:0 -map 1:0 -t 20ms "$@"

doc/file.mp4: Makefile
	ffmpeg -y -f lavfi -i sine -f lavfi -i testsrc -c:a aac -c:v h264 -f mp4 -t 20ms "$@"

.PHONY: gogenerate
gogenerate:
	go generate -x ./...

.PHONY: lint
lint:
# bump: make-golangci-lint /golangci-lint@v([\d.]+)/ git:https://github.com/golangci/golangci-lint.git|^1
	go run github.com/golangci/golangci-lint/cmd/golangci-lint@v1.45.0 run

.PHONY: depgraph.svg
depgraph.svg:
	go run github.com/kisielk/godepgraph@latest github.com/wader/fq | dot -Tsvg -o godepgraph.svg

# make memprof ARGS=". test.mp3"
# make cpuprof ARGS=". test.mp3"
.PHONY: prof
prof:
	go build -tags profile -o fq.prof fq.go
	CPUPROFILE=fq.cpu.prof MEMPROFILE=fq.mem.prof ./fq.prof ${ARGS}
.PHONY: memprof
memprof: prof
	go tool pprof -http :5555 fq.prof fq.mem.prof

.PHONY: cpuprof
cpuprof: prof
	go tool pprof -http :5555 fq.prof fq.cpu.prof

.PHONY: update-gomod
update-gomod:
	GOPROXY=direct go get -d github.com/wader/readline@fq
	GOPROXY=direct go get -d github.com/wader/gojq@fq
	go mod tidy

# TODO: as decode recovers panic and "repanics" unrecoverable errors this is a bit hacky at the moment
# fuzz code is not suppose to print to stderr so log to file
.PHONY: fuzz
fuzz:
# in other terminal: tail -f /tmp/repanic
	REPANIC_LOG=/tmp/repanic gotip test -tags fuzz -v -run Fuzz -fuzz=Fuzz ./format/

# usage: make release VERSION=0.0.1
# tag forked dependeces for history and to make then stay around
.PHONY: release
release: WADER_GOJQ_COMMIT=$(shell go list -m -f '{{.Version}}' github.com/wader/gojq | sed 's/.*-\(.*\)/\1/')
release: WADER_READLINE_COMMIT=$(shell go list -m -f '{{.Version}}' github.com/wader/readline | sed 's/.*-\(.*\)/\1/')
release:
	@echo "# wader/fq":
	@echo "# make sure head is at wader/master"
	@echo git fetch wader
	@echo git show
	@echo make lint test doc
	@echo go mod tidy
	@echo git diff
	@echo
	@echo "sed 's/version = "\\\(.*\\\)"/version = \"${VERSION}\"/' fq.go > fq.go.new && mv fq.go.new fq.go"
	@echo git add fq.go
	@echo git commit -m \"fq: Update version to ${VERSION}\"
	@echo git push wader master
	@echo
	@echo "# make sure head master commit CI was successful"
	@echo open https://github.com/wader/fq/commit/master
	@echo git tag v${VERSION}
	@echo
	@echo "# wader/gojq:"
	@echo git tag fq-v${VERSION} ${WADER_GOJQ_COMMIT}
	@echo git push wader fq-v${VERSION}:fq-v${VERSION}
	@echo
	@echo "# wader/readline:"
	@echo git tag fq-v${VERSION} ${WADER_READLINE_COMMIT}
	@echo git push wader fq-v${VERSION}:fq-v${VERSION}
	@echo
	@echo "# wader/fq":
	@echo git push wader v${VERSION}:v${VERSION}
	@echo "# edit draft release notes and publish"
