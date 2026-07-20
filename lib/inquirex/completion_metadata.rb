# frozen_string_literal: true

require "ostruct"
require "json"

module Inquirex
  # An OpenStruct describing how a flow reached completion: which rendering
  # engine collected the answers, and any environment details that renderer
  # chose to attach (host uname, user, IP addresses, terminal, ...).
  #
  # Only :engine and :engine_version are required members — enforced at
  # construction. Everything else is free-form OpenStruct behavior: unset
  # members read as nil, assignment creates members, nested OpenStructs
  # (e.g. uname) are welcome.
  #
  # @example
  #   meta = Inquirex::CompletionMetadata.new(
  #     engine: "inquirex-tty", engine_version: "0.5.0",
  #     uname: OpenStruct.new(Etc.uname)
  #   )
  #   meta.engine          # => "inquirex-tty"
  #   meta.uname.machine   # => "arm64"
  #   meta.hostname        # => nil (unset members read as nil)
  #   meta.to_h            # => plain nested Hash, JSON-ready
  class CompletionMetadata < OpenStruct
    # Members that must be provided at construction; everything else is optional.
    REQUIRED_MEMBERS = %i[engine engine_version].freeze

    # Exists solely to make :engine and :engine_version required keywords —
    # OpenStruct itself would accept anything.
    #
    # @param engine [String] rendering front-end name (e.g. "inquirex-tty")
    # @param engine_version [String] rendering front-end version
    # @param extra [Hash] any additional, optional members
    def initialize(engine:, engine_version:, **extra) # rubocop:disable Lint/UselessMethodDefinition
      super
    end

    # Rebuilds an instance from a hash (e.g. persisted engine state after a
    # JSON round-trip). Keys may be strings or symbols; nested hashes come
    # back as OpenStructs so dot-access survives the round-trip.
    #
    # @param hash [Hash, nil]
    # @return [CompletionMetadata, nil] nil when hash is nil or empty
    # @raise [ArgumentError] when :engine or :engine_version is missing
    def self.from_h(hash)
      return nil if hash.nil? || hash.empty?

      members = hash.to_h { |k, v| [k.to_sym, v.is_a?(Hash) ? OpenStruct.new(v) : v] }
      new(**members)
    end

    # OpenStruct#to_h is shallow; deep-convert nested OpenStructs (uname et
    # al.) so state serialization and JSON output stay plain data.
    #
    # @return [Hash]
    def to_h
      deep_plain(super)
    end

    # @return [String] JSON representation
    def to_json(*)
      JSON.generate(to_h)
    end

    # @return [String] debug representation of the deep-plain member hash
    def inspect
      "#<Inquirex::CompletionMetadata #{to_h.inspect}>"
    end

    private

    def deep_plain(value)
      case value
      when OpenStruct then deep_plain(value.to_h)
      when Hash       then value.transform_values { |v| deep_plain(v) }
      when Array      then value.map { |v| deep_plain(v) }
      else value
      end
    end
  end
end
