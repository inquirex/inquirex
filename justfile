# Tell 'just' to run bash, source our setup script, then execute the recipe
set shell := ["bash", "-c"]

version := `grep VERSION lib/inquirex/version.rb | awk '{print $3}' | tr -d '"' | tr -d '\n'`
rbenv   := 'eval "$(rbenv init bash)"; bundle exec '
repo    := 'git@github.com:inquirex/inquirex.git'

[no-exit-message]
recipes:
    just --choose

# Sync all dependencies
install:
    bin/setup

build: install

# Lint and reformat files
lint:
    {{ rbenv }} rubocop

# Lint and reformat files (-a) — pass -A as an argument
format *args:
    {{ rbenv }} rubocop -a {{ args }}
    /usr/bin/find . -name '*.md' -exec mdformat --wrap no {} \; -print

# Run all the tests
test *args: 
    export ENVIRONMENT=test; {{ rbenv }} rspec {{args}}

# Run tests with coverage
test-coverage *args:
    export ENVIRONMENT=test; export COVERAGE=true; {{ rbenv }} rspec {{ args }}

ci: lint test-coverage 

alias check-all := ci

clean:
    #!/usr/bin/env bash
    @find . -name .DS_Store -delete -print || true
    @rm -rf tmp/*

# Run all lefthook pre-commit hooks
lefthook:
    {{ rbenv }} lefthook run pre-commit --all-files

# Print current gem version
version:
    @echo "{{ version }}"

# Clobber
clobber: 
    {{ rbenv }} rake clobber

# Generate documentation
doc: 
    #!/usr/bin/env bash
    {{ rbenv }} rake doc

# Create
publish: build
    {{ rbenv }} rake release[remote]

# Tag v{{ version }}, publish the GH release, & refresh the Homebrew tap.
release:
    git fetch --tags
    git tag -f "v{{ version }}"
    git push -f --tags
    gh release delete -y "v{{ version }}" --repo {{ repo }} 2>/dev/null || true
    gh release create "v{{ version }}" --generate-notes --repo {{ repo }}
