# frozen_string_literal: true

module Inquirex
  module DSL
    # Builds a Definition from the declarative DSL block used in Inquirex.define.
    # Provides start, meta, and all verb methods (ask, say, header, btw, warning, confirm).
    class FlowBuilder
      include RuleHelpers

      # @param id [String, nil] optional flow identifier
      # @param version [String] semver
      def initialize(id: nil, version: "1.0.0")
        @flow_id = id
        @flow_version = version
        @start_step_id = nil
        @nodes = {}
        @meta = {}
      end

      # Sets the entry step id for the flow.
      #
      # @param step_id [Symbol]
      def start(step_id)
        @start_step_id = step_id
      end

      # Sets frontend metadata: title, subtitle, and brand information.
      #
      # @param title [String, nil]
      # @param subtitle [String, nil]
      # @param brand [Hash, nil] e.g. { name: "Acme", color: "#2563eb" }
      def meta(title: nil, subtitle: nil, brand: nil)
        @meta[:title] = title if title
        @meta[:subtitle] = subtitle if subtitle
        @meta[:brand] = brand if brand
      end

      # Defines a question step that collects typed input from the user.
      #
      # @param id [Symbol] step id
      # @yield block evaluated in StepBuilder (type, question, options, transition, etc.)
      def ask(id, &)
        add_step(id, :ask, &)
      end

      # Defines an informational message step (no input collected).
      #
      # @param id [Symbol] step id
      def say(id, &)
        add_step(id, :say, &)
      end

      # Defines a section heading step (no input collected).
      #
      # @param id [Symbol] step id
      def header(id, &)
        add_step(id, :header, &)
      end

      # Defines an admonition or sidebar note step (no input collected).
      #
      # @param id [Symbol] step id
      def btw(id, &)
        add_step(id, :btw, &)
      end

      # Defines an important alert step (no input collected).
      #
      # @param id [Symbol] step id
      def warning(id, &)
        add_step(id, :warning, &)
      end

      # Defines a yes/no confirmation gate (collects a boolean answer).
      #
      # @param id [Symbol] step id
      def confirm(id, &)
        add_step(id, :confirm, &)
      end

      # Produces the frozen Definition.
      #
      # @return [Definition]
      # @raise [Errors::DefinitionError] if start was not set or no steps were defined
      def build
        raise Errors::DefinitionError, "No start step defined" if @start_step_id.nil?
        raise Errors::DefinitionError, "No steps defined" if @nodes.empty?

        Definition.new(
          start_step_id: @start_step_id,
          nodes:         @nodes,
          id:            @flow_id,
          version:       @flow_version,
          meta:          @meta
        )
      end

      private

      def add_step(id, verb, &block)
        builder = StepBuilder.new(verb)
        builder.instance_eval(&block) if block
        @nodes[id.to_sym] = builder.build(id)
      end
    end
  end
end
