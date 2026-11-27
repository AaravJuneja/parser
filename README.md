# Bash TOML parser

This parser reads TOML 1.1.0 and writes JSON to standard output. I picked TOML parsing as a small project and thought it would be fun to do it in one Bash file (totally didnt recreate the popular multi-file ones with minor changes of my own)

## Requirements

Bash 4 or newer is the only runtime dependency. The parser was tested with Bash 4.0 and 5.3.9 on Linux. Go is only needed for [Testing](#testing)

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/AaravJuneja/parser/master/parser.sh -o parser.sh
```

## Run

Try the included `yeehaw.toml` example. If you downloaded just the script, fetch the example first:

```sh
curl -fsSL https://raw.githubusercontent.com/AaravJuneja/parser/master/yeehaw.toml -o yeehaw.toml
```

```sh
bash parser.sh yeehaw.toml
```

The output is a single JSON object. Here's an extract:

```json
{
  "title": "Shakespeare",
  "team": "Syndication",
  "server": {
    "host": "balcony.syndication",
    "port": 1909
  }
}
```

Pass `-` to read TOML from standard input:

```sh
printf 'answer = 42\n #kevin' | bash parser.sh -
```

```json
{
  "answer": 42
}
```

## Limits

Since plain JSON has no native representation for dates, times or non finite floats (`inf`, `-inf` and `nan`) the parser emits them as strings

## Testing

All 681 upstream TOML 1.1 decoder cases passed: 214 valid and 467 invalid. To run them:

```sh
go run github.com/toml-lang/toml-test/v2/cmd/toml-test@v2.2.0 test -toml=1.1 -decoder 'bash ./parser.sh --toml-test'
```

`bash parser.sh --toml-test` reads TOML from standard input and emits tagged JSON for the test suite

## License

The parser is [MIT licensed](LICENSE). The TOML 1.1.0 reference files in `docs/` retain the [MIT license and copyright notice](docs/LICENSE)
