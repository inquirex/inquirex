# frozen_string_literal: true

# The allowlist is only trustworthy while it still describes the DSL. This file
# is the mechanism that keeps it honest: it compares every entry against the
# builder that actually implements the word — its existence, its positional
# arity, its keyword list — and fails the build when the two drift apart. Add a
# verb or a setter to FlowBuilder, StepBuilder, RuleHelpers or an Actions effect
# without making an allowlist decision, and these examples say so by name.
V = Inquirex::SafeSource::Vocabulary

# scope => how to find the real method behind an allowlisted name.
DSL_SIGNATURES = {
  rule:   ->(name) { Inquirex::DSL::RuleHelpers.instance_method(name) },
  flow:   ->(name) { Inquirex::DSL::FlowBuilder.instance_method(name) },
  step:   ->(name) { Inquirex::DSL::StepBuilder.instance_method(name) },
  email:  ->(name) { Inquirex::DSL::EmailBuilder.instance_method(name) },
  # Effects are not builder methods: ActionBuilder resolves them through the
  # registry, so the keyword list lives on the effect's constructor.
  action: ->(name) { Inquirex::Actions.lookup(name).instance_method(:initialize) }
}.freeze

RSpec.describe Inquirex::SafeSource::Vocabulary do
  # The parts of a real signature the allowlist has to agree with.
  #
  # @param method [UnboundMethod]
  # @return [Hash{Symbol => Object}]
  def signature_of(method)
    params = method.parameters
    {
      required:          params.count { |type, _| type == :req },
      optional:          params.count { |type, _| type == :opt },
      rest:              params.any? { |type, _| type == :rest },
      keywords:          params.filter_map { |type, name| name if %i[key keyreq].include?(type) },
      required_keywords: params.filter_map { |type, name| name if type == :keyreq },
      keyrest:           params.any? { |type, _| type == :keyrest }
    }
  end

  V.scopes.each do |scope|
    describe "the #{scope} scope" do
      it "has an allowlist decision for every DSL word its builder implements" do
        undeclared = V.undeclared_names(scope)

        expect(undeclared).to be_empty,
          "#{undeclared.inspect} exist in the DSL but are neither allowed nor excluded — " \
          "call Vocabulary.allow or Vocabulary.exclude for each"
      end

      it "declares nothing its builder does not implement" do
        stale = V.stale_names(scope)

        expect(stale).to be_empty, "#{stale.inspect} are declared but no longer exist in the DSL"
      end

      V.allowed_names(scope).each do |name|
        describe "`#{name}`" do
          subject(:spec) { V.spec_for(scope, name) }

          let(:signature) { signature_of(DSL_SIGNATURES.fetch(scope).call(name)) }
          let(:declared_keywords) { spec.keywords.to_h.keys - [V::ANY_OTHER] }
          let(:catch_all?) { spec.keywords.to_h.key?(V::ANY_OTHER) }

          it "declares as many positional arguments as the real method accepts" do
            case spec.positional
            when Array
              expect(spec.positional.length).to be >= signature[:required]
              ceiling = signature[:required] + signature[:optional]
              expect(spec.positional.length).to be <= ceiling unless signature[:rest]
            when Hash
              expect(signature[:rest] || signature[:optional].positive?).to be(true)
            end
          end

          it "declares only keywords the real method accepts" do
            expect(declared_keywords - signature[:keywords]).to be_empty unless signature[:keyrest]
          end

          it "declares every keyword the real method requires" do
            expect(signature[:required_keywords] - declared_keywords).to be_empty
          end

          # A catch-all is the honest description of a method that really does
          # take an open keyword list; used anywhere else it would be laxity
          # dressed up as a specification.
          it "opens the keyword list only where the real method takes **rest" do
            expect(signature[:keyrest]).to be(true) if catch_all?
          end

          it "opens a block only into a registered scope" do
            expect(V.scope?(spec.block)).to be(true) unless spec.block == :forbidden
          end
        end
      end
    end
  end

  describe "the flow verbs" do
    it "are derived from Node::VERBS rather than hand-listed" do
      expect(Inquirex::Node::VERBS).to all(satisfy { |verb| V.spec_for(:flow, verb) })
    end

    it "each open a step block" do
      blocks = Inquirex::Node::VERBS.map { |verb| V.spec_for(:flow, verb).block }

      expect(blocks).to all(eq(:step))
    end
  end

  describe "the entry point" do
    subject(:keywords) { described_class.entry_spec.keywords.keys }

    it "accepts exactly the keywords Inquirex.define accepts" do
      accepted = Inquirex.method(:define).parameters
                         .filter_map { |type, name| name if %i[key keyreq].include?(type) }

      expect(keywords).to match_array(accepted)
    end
  end

  describe "the excluded words" do
    it "records a reason for each, since the validator quotes it back" do
      reasons = described_class.scopes.flat_map do |scope|
        described_class.excluded_names(scope).map { |name| described_class.exclusion_for(scope, name) }
      end

      expect(reasons).to all(be_a(String).and(satisfy { |reason| reason.length > 20 }))
    end

    it "excludes the one construct that is arbitrary Ruby by definition" do
      expect(described_class.excluded_names(:step)).to include(:compute)
    end

    # `run` and `webhook` used to be excluded here. They were deleted from the
    # gem in 0.7.0 instead, which is a stronger guarantee than refusing them in
    # safe mode: there is no `unsafe: true` that brings them back.
    it "has nothing left to exclude in the deprecated action scope" do
      expect(described_class.excluded_names(:action)).to be_empty
      expect(Inquirex::Actions.types).to contain_exactly(:send_email)
    end
  end

  describe "the top-level send_email verb" do
    it "opens an email block taking no positional arguments" do
      spec = described_class.spec_for(:flow, :send_email)

      expect(spec.block).to eq(:email)
      expect(spec.positional).to be_empty
    end

    it "allows exactly the setters EmailBuilder implements" do
      expect(described_class.allowed_names(:email))
        .to match_array(Inquirex::DSL::EmailBuilder.public_instance_methods(false) - described_class::PLUMBING)
    end

    it "accepts only static strings, so no Ruby can reach a template" do
      kinds = described_class.allowed_names(:email).map { |name| described_class.spec_for(:email, name).positional }

      expect(kinds).to all(eq(%i[string]))
    end
  end

  describe ".label_for" do
    it { expect(described_class.label_for(:step)).to eq("a step") }
    it { expect(described_class.label_for(:nowhere)).to eq("an unknown") }
  end

  describe "extension by downstream gems" do
    around do |example|
      example.run
      described_class.reset!
    end

    let(:source) do
      <<~RUBY
        Inquirex.define do
          start :a

          clarify :a do
            prompt "Extract the business type."
          end
        end
      RUBY
    end

    it "rejects an unregistered verb" do
      expect(Inquirex::SafeSource.validate(source)).to include(a_string_matching(/`clarify` is not allowed/))
    end

    it "accepts it once the gem registers its vocabulary" do
      described_class.register_scope(:llm_step, label: "an LLM step")
      described_class.allow(:flow, :clarify, positional: %i[symbol], block: :llm_step)
      described_class.allow(:llm_step, :prompt, positional: %i[literal])

      expect(Inquirex::SafeSource.validate(source)).to be_empty
    end

    it "still refuses what the extension did not allow" do
      described_class.register_scope(:llm_step, label: "an LLM step")
      described_class.allow(:flow, :clarify, positional: %i[symbol], block: :llm_step)
      described_class.exclude(:llm_step, :fallback, "a Ruby block cannot be validated")

      expect(Inquirex::SafeSource.validate(source))
        .to include(a_string_matching(/`prompt` is not allowed inside an LLM step block/))
    end

    it "refuses to register against an unknown scope" do
      expect { described_class.allow(:nowhere, :x) }.to raise_error(ArgumentError, /Unknown SafeSource scope/)
      expect { described_class.exclude(:nowhere, :x, "why") }
        .to raise_error(ArgumentError, /Unknown SafeSource scope/)
    end

    it "supports an at-most-one positional argument" do
      described_class.register_scope(:llm_step, label: "an LLM step")
      described_class.allow(:flow, :clarify, positional: %i[symbol], block: :llm_step)
      described_class.allow(:llm_step, :from_all, positional: { optional: :literal })
      flow = ->(args) { source.sub("prompt \"Extract the business type.\"", "from_all #{args}") }

      expect(Inquirex::SafeSource.validate(flow.call(""))).to be_empty
      expect(Inquirex::SafeSource.validate(flow.call("true"))).to be_empty
      expect(Inquirex::SafeSource.validate(flow.call("true, false")))
        .to contain_exactly(/`from_all` takes at most 1 argument/)
    end

    it "reports no binding for a scope that declared none" do
      described_class.register_scope(:llm_step, label: "an LLM step")

      expect(described_class.governed_names(:llm_step)).to be_empty
      expect(described_class.stale_names(:llm_step)).to be_empty
    end
  end
end
