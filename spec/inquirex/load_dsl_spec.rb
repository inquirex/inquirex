# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe "Inquirex.load_dsl" do
  subject(:definition) { Inquirex.load_dsl(source) }

  let(:source) { DslPayloads.accepted.fetch("minimal") }

  it { is_expected.to be_a(Inquirex::Definition) }
  its(:start_step_id) { is_expected.to eq(:hello) }

  describe "the legitimate corpus" do
    # Guarding must not change what the DSL means: the definition validation
    # lets through has to be identical to the unguarded one.
    DslPayloads.accepted.each_key do |label|
      it "loads #{label} into the same definition it would unguarded" do
        text = DslPayloads.accepted.fetch(label)

        expect(Inquirex.load_dsl(text).to_h).to eq(Inquirex.load_dsl(text, unsafe: true).to_h)
      end
    end
  end

  describe "attack payloads" do
    DslPayloads.rejected.each_key do |label|
      it "refuses to load #{label}" do
        expect { Inquirex.load_dsl(DslPayloads.rejected.fetch(label)) }
          .to raise_error(Inquirex::Errors::UnsafeSourceError)
      end
    end
  end

  describe "host-configurable ceilings" do
    around do |example|
      bytes = Inquirex::SafeSource.max_source_bytes
      example.run
      Inquirex::SafeSource.max_source_bytes = bytes
    end

    it "honours a lowered SafeSource ceiling" do
      Inquirex::SafeSource.max_source_bytes = 32

      expect { definition }.to raise_error(Inquirex::Errors::UnsafeSourceError, /over the 32-byte limit/)
    end

    it "honours a per-call ceiling" do
      expect { Inquirex.load_dsl(source, max_depth: 2) }
        .to raise_error(Inquirex::Errors::UnsafeSourceError, /nests deeper than 2 levels/)
    end
  end

  describe "validation happens before evaluation" do
    # The whole point of the fix is the *ordering*: a payload must be rejected
    # while it is still text. Asserting that load_dsl raised is not enough —
    # eval could have run first and raised afterwards — so the assertion is
    # that the payload's side effect never happened.
    let(:tmpdir) { Dir.mktmpdir("inquirex-safe-source") }
    let(:canary) { File.join(tmpdir, "canary.txt") }
    let(:payload) do
      <<~RUBY
        Inquirex.define do
          start :a

          say :a do
            text File.write("#{canary}", "pwned").to_s
          end
        end
      RUBY
    end

    after { FileUtils.rm_rf(tmpdir) }

    it "raises before the payload can write its file" do
      expect { Inquirex.load_dsl(payload) }.to raise_error(Inquirex::Errors::UnsafeSourceError)
      expect(File).not_to exist(canary)
    end

    # Positive control: without the guard the very same payload does execute,
    # which is what proves the assertion above is testing something.
    it "does write the file when validation is skipped" do
      expect { Inquirex.load_dsl(payload, unsafe: true) }.not_to raise_error
      expect(File).to exist(canary)
    end
  end

  describe "unsafe: true" do
    let(:source) do
      <<~RUBY
        Inquirex.define do
          start :count

          ask :count do
            type :integer
            question "How many?"
            default { |answers| 3 }
            transition to: :total
          end

          ask :total do
            type :integer
            compute { |answers| answers[:count].to_i * 2 }
          end
        end
      RUBY
    end

    it "evaluates the Ruby blocks safe mode cannot validate" do
      expect(Inquirex.load_dsl(source, unsafe: true).step(:count).default).to be_a(Proc)
    end

    it "is the only way to load such a flow" do
      expect { definition }.to raise_error(Inquirex::Errors::UnsafeSourceError, /`compute`/)
    end
  end

  describe "errors raised by evaluation itself" do
    it "wraps a definition error from the builder" do
      expect { Inquirex.load_dsl(%(Inquirex.define do\n  meta title: "x"\nend\n)) }
        .to raise_error(Inquirex::Errors::DefinitionError, /DSL evaluation error: No start step/)
    end

    it "wraps a syntax error reached through the escape hatch" do
      expect { Inquirex.load_dsl("Inquirex.define do\n", unsafe: true) }
        .to raise_error(Inquirex::Errors::DefinitionError, /DSL syntax error/)
    end

    it "reports a syntax error as a violation in safe mode" do
      expect { Inquirex.load_dsl("Inquirex.define do\n") }
        .to raise_error(Inquirex::Errors::UnsafeSourceError, /syntax error/)
    end
  end
end
