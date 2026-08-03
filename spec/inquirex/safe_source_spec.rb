# frozen_string_literal: true

RSpec.describe Inquirex::SafeSource do
  describe "the legitimate corpus" do
    DslPayloads.accepted.each_key do |label|
      it "accepts #{label}" do
        expect(described_class.validate(DslPayloads.accepted.fetch(label))).to be_empty
      end
    end
  end

  describe "attack payloads" do
    DslPayloads.rejected.each_key do |label|
      it "rejects #{label}" do
        expect(described_class.validate(DslPayloads.rejected.fetch(label))).not_to be_empty
      end
    end

    # The attack corpus is worthless if a payload silently stops being hostile
    # (an interpolating heredoc in the spec, a typo that makes it valid DSL).
    # Every payload must therefore fail the allowlist for a *structural*
    # reason, never merely because Ruby could not parse it.
    it "rejects every payload on structure rather than on syntax" do
      syntax_only = DslPayloads.rejected.select do |_label, source|
        described_class.validate(source).all? { |violation| violation.include?("syntax error") }
      end

      expect(syntax_only).to be_empty
    end
  end

  describe ".validate" do
    it "reports a syntax error with its line" do
      expect(described_class.validate("Inquirex.define do\n  start :a\n"))
        .to include(a_string_matching(/^line \d+: syntax error/))
    end

    it "rejects anything that is not a String" do
      expect(described_class.validate(42)).to contain_exactly("the DSL must be a String, got Integer")
    end

    it "rejects nil as blank" do
      expect(described_class.validate(nil)).to contain_exactly("the DSL is blank")
    end
  end

  describe ".safe?" do
    it { expect(described_class).to be_safe(DslPayloads.accepted.fetch("minimal")) }
    it { expect(described_class).not_to be_safe(DslPayloads.rejected.fetch("system")) }
    it { expect(described_class).not_to be_safe(nil) }
  end

  describe ".validate!" do
    subject(:call) { described_class.validate!(source) }

    context "with safe source" do
      let(:source) { DslPayloads.accepted.fetch("minimal") }

      it { is_expected.to eq(source) }
    end

    context "with a payload" do
      let(:source) { DslPayloads.rejected.fetch("ENV") }

      it { expect { call }.to raise_error(Inquirex::Errors::UnsafeSourceError, /DSL rejected:/) }
    end
  end

  describe "error reporting" do
    subject(:error) do
      described_class.validate!(DslPayloads.rejected.fetch("ENV"))
      nil
    rescue Inquirex::Errors::UnsafeSourceError => e
      e
    end

    its(:message) { is_expected.to start_with("DSL rejected:") }
    its(:violations) { is_expected.to all(match(/^line \d+: /)) }

    it "is rescued by the existing Inquirex error handling" do
      expect(Inquirex::Errors::UnsafeSourceError.ancestors).to include(Inquirex::Errors::DefinitionError)
    end

    it "reports at most #{Inquirex::SafeSource::Validator::MAX_REPORTED} violations" do
      noisy = "Inquirex.define do\n#{"  sabotage :x\n" * 50}end\n"

      expect(described_class.validate(noisy).size).to eq(Inquirex::SafeSource::Validator::MAX_REPORTED)
    end

    it "names the excluded verb and its reason, and points at the escape hatch" do
      expect(described_class.validate(DslPayloads.rejected.fetch("compute block")))
        .to contain_exactly(/`compute` is not available in safe mode: .*payload.*unsafe: true/m)
    end

    # These were excluded in safe mode until the gem deleted them outright,
    # which is the stronger guarantee — there is no `unsafe: true` that brings
    # them back. They are now simply words the DSL does not have, and the
    # message says so rather than implying a mode where they would work.
    it "reports the deleted capabilities as unknown words rather than exclusions" do
      expect(described_class.validate(DslPayloads.rejected.fetch("webhook effect")))
        .to contain_exactly(/`action` is not allowed inside a flow block/)
      expect(described_class.validate(DslPayloads.rejected.fetch("allowed_domains")))
        .to contain_exactly(/`allowed_domains` is not allowed inside a flow block/)
      expect(described_class.validate(DslPayloads.rejected.fetch("action run block")))
        .to contain_exactly(/`action` is not allowed inside a flow block/)
    end

    it "refuses a file: body, so a template cannot name a path" do
      expect(described_class.validate(DslPayloads.rejected.fetch("send_email file body")))
        .to contain_exactly(/`send_email` text: must be a plain string/)
    end
  end

  describe "the size cap" do
    subject(:violations) { described_class.validate(source) }

    let(:padding) { "# #{"x" * 78}\n" }
    let(:source) { "Inquirex.define do\n  start :a\n#{padding * copies}end\n" }

    context "when just under the cap" do
      let(:copies) { (described_class::DEFAULT_MAX_SOURCE_BYTES / padding.bytesize) - 2 }

      it { is_expected.to be_empty }
    end

    context "when over the cap" do
      let(:copies) { (described_class::DEFAULT_MAX_SOURCE_BYTES / padding.bytesize) + 2 }

      it { is_expected.to contain_exactly(/over the #{described_class::DEFAULT_MAX_SOURCE_BYTES}-byte limit/) }

      it "is accepted when the host raises the ceiling for the call" do
        expect(described_class.validate(source, max_bytes: 1_000_000)).to be_empty
      end
    end
  end

  describe "the depth cap" do
    subject(:violations) { described_class.validate(source) }

    let(:source) do
      <<~RUBY
        Inquirex.define do
          start :a

          ask :a do
            type :string
            skip_if #{"all(" * nesting}not_empty(:a)#{")" * nesting}
          end
        end
      RUBY
    end

    context "when nesting stays within the cap" do
      let(:nesting) { 5 }

      it { is_expected.to be_empty }
    end

    context "when nesting exceeds the cap" do
      let(:nesting) { described_class::DEFAULT_MAX_DEPTH + 5 }

      it { is_expected.to contain_exactly(/nests deeper than #{described_class::DEFAULT_MAX_DEPTH} levels/) }

      it "is accepted when the host raises the ceiling for the call" do
        expect(described_class.validate(source, max_depth: 100)).to be_empty
      end
    end
  end

  describe "host-configurable ceilings" do
    around do |example|
      bytes = described_class.max_source_bytes
      depth = described_class.max_depth
      example.run
      described_class.max_source_bytes = bytes
      described_class.max_depth = depth
    end

    let(:source) { DslPayloads.accepted.fetch("minimal") }

    it "applies a lowered size ceiling" do
      described_class.max_source_bytes = 32

      expect(described_class.validate(source)).to contain_exactly(/over the 32-byte limit/)
    end

    it "applies a lowered depth ceiling" do
      described_class.max_depth = 2

      expect(described_class.validate(source)).to all(include("nests deeper than 2 levels"))
    end
  end
end
