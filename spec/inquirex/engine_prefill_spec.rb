# frozen_string_literal: true

require "rspec/its"

RSpec.describe Inquirex::Engine, "#prefill!" do
  subject(:engine) { described_class.new(definition) }

  let(:definition) do
    Inquirex.define id: "prefill-demo" do
      start :filing_status

      ask :filing_status do
        type :enum
        question "Filing status?"
        options %w[single married]
        skip_if not_empty(:filing_status)
        transition to: :dependents
      end

      ask :dependents do
        type :integer
        question "How many dependents?"
        skip_if not_empty(:dependents)
        transition to: :done
      end

      say :done do
        text "Thanks."
      end
    end
  end

  it "merges values into top-level answers" do
    engine.prefill!(filing_status: "single", dependents: 2)
    expect(engine.answers).to include(filing_status: "single", dependents: 2)
  end

  it "auto-advances past steps whose skip_if becomes satisfied" do
    engine.prefill!(filing_status: "single", dependents: 2)
    expect(engine.current_step_id).to eq(:done)
  end

  it "only skips the currently-asked step when a partial prefill lands" do
    engine.prefill!(filing_status: "single")
    expect(engine.current_step_id).to eq(:dependents)
    expect(engine.answers).to include(filing_status: "single")
  end

  it "ignores nil values" do
    engine.prefill!(filing_status: nil, dependents: 2)
    expect(engine.answers).not_to have_key(:filing_status)
    expect(engine.answers).to include(dependents: 2)
    expect(engine.current_step_id).to eq(:filing_status)
  end

  it "ignores empty strings and empty arrays" do
    engine.prefill!(filing_status: "", dependents: 2)
    expect(engine.answers).not_to have_key(:filing_status)
    expect(engine.current_step_id).to eq(:filing_status)
  end

  it "does not clobber already-answered keys" do
    engine.answer("married")
    engine.prefill!(filing_status: "single", dependents: 3)
    expect(engine.answers[:filing_status]).to eq("married")
    expect(engine.answers[:dependents]).to eq(3)
  end

  it "accepts string keys too" do
    engine.prefill!("filing_status" => "single")
    expect(engine.answers).to include(filing_status: "single")
  end

  it "is a no-op for non-hash input" do
    expect { engine.prefill!(nil) }.not_to raise_error
    expect { engine.prefill!("string") }.not_to raise_error
    expect(engine.current_step_id).to eq(:filing_status)
  end

  context "with a multi-select step" do
    let(:definition) do
      Inquirex.define id: "prefill-multi-demo" do
        start :filing_status

        ask :filing_status do
          type :enum
          question "Filing status?"
          options %w[single married]
          skip_if not_empty(:filing_status)
          transition to: :income_types
        end

        ask :income_types do
          type :multi_enum
          question "Income types?"
          options %w[W2 business rental crypto]
          skip_if not_empty(:income_types)
          transition to: :done
        end

        say :done do
          text "Thanks."
        end
      end
    end

    before { engine.prefill!(filing_status: "married", income_types: ["business"]) }

    # Single-select extraction is deterministic — skip the question. A
    # multi-select extraction is a hint the user confirms and may extend, so
    # the question is still asked with the choices preselected.
    its(:current_step_id) { is_expected.to eq(:income_types) }
    its(:answers) { is_expected.to include(filing_status: "married") }
    its(:answers) { is_expected.not_to have_key(:income_types) }
    its(:suggestions) { is_expected.to eq(income_types: ["business"]) }

    it "exposes the suggestion for the step" do
      expect(engine.suggestion_for(:income_types)).to eq(["business"])
      expect(engine.suggestion_for("income_types")).to eq(["business"])
      expect(engine.suggestion_for(:filing_status)).to be_nil
    end

    it "wraps a scalar suggestion in an array" do
      fresh = described_class.new(definition)
      fresh.prefill!(income_types: "rental")
      expect(fresh.suggestion_for(:income_types)).to eq(["rental"])
    end

    it "clears the suggestion once the step is answered" do
      engine.answer(%w[business rental])
      expect(engine.suggestions).to be_empty
      expect(engine.answers[:income_types]).to eq(%w[business rental])
      expect(engine.current_step_id).to eq(:done)
    end

    it "does not suggest for a step that is already answered" do
      engine.answer(%w[W2])
      engine.prefill!(income_types: ["crypto"])
      expect(engine.suggestion_for(:income_types)).to be_nil
      expect(engine.answers[:income_types]).to eq(%w[W2])
    end

    it "round-trips suggestions through to_state and from_state" do
      state = JSON.parse(engine.to_state.to_json)
      restored = described_class.from_state(definition, state)
      expect(restored.suggestion_for(:income_types)).to eq(["business"])
      expect(restored.current_step_id).to eq(:income_types)
    end
  end
end
