set shell := ["bash", "-lc"]

rbenv := 'eval "$(rbenv init -)"'

[no-exit-message]
recipes:
    @just --choose

# Sync all dependencies
install:
    {{rbenv}} && bin/setup

# Lint and reformat files
lint-fix *args:
    {{rbenv}} && bundle exec rubocop -a

# Lint and reformat files
lint:
    {{rbenv}} && bundle exec rubocop

# Run all the tests
test *args: 
    {{rbenv}} &&  ENVIRONMENT=test bundle exec rspec {{args}}

# Run tests with coverage
test-coverage *args:
    ENVIRONMENT=test COVERAGE=true bundle exec rspec

clean:
    #!/usr/bin/env bash
    find . -name .DS_Store -delete -print || true
    rm -rf tmp/*

# Run all lefthook pre-commit hooks
ci:
    {{rbenv}} && lefthook run pre-commit --all-files
