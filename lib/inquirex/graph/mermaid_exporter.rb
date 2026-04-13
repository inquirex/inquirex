# frozen_string_literal: true

module Inquirex
  module Graph
    # Exports a flow Definition to Mermaid flowchart syntax for visualization.
    # Node labels show verb + truncated question/text; edges show condition labels.
    class MermaidExporter
      MAX_LABEL_LENGTH = 50

      attr_reader :definition

      # @param definition [Definition]
      def initialize(definition)
        @definition = definition
      end

      # Generates Mermaid flowchart TD (top-down) source.
      #
      # @return [String]
      def export
        lines = ["flowchart TD"]

        @definition.steps.each_value do |node|
          lines << "  #{node.id}[\"#{node_label(node)}\"]"

          node.transitions.each do |transition|
            label = transition.condition_label
            lines << if label == "always"
                       "  #{node.id} --> #{transition.target}"
                     else
                       "  #{node.id} -->|\"#{label}\"| #{transition.target}"
                     end
          end
        end

        lines.join("\n")
      end

      private

      def node_label(node)
        content = node.collecting? ? node.question : node.text
        prefix = node.verb == :ask ? "" : "[#{node.verb}] "
        truncate("#{prefix}#{content}")
      end

      def truncate(text)
        return "" if text.nil?
        return text if text.length <= MAX_LABEL_LENGTH

        "#{text[0, MAX_LABEL_LENGTH]}..."
      end
    end
  end
end
