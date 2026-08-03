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

  # Regression: the `prompt :auto` extraction scenario. The flow declares NO
  # skip_if rules — prefilled questions must skip anyway, because a prefilled
  # single-select answer is a fact, and re-asking it invites the user to
  # overwrite a correct extraction with a stray keypress.
  context "without skip_if rules (extract :auto scenario)" do
    let(:definition) do
      Inquirex.define id: "auto-extract-demo" do
        start :residency_status

        ask :residency_status do
          type :enum
          question "Which best describes your US tax residency?"
          options({
            "us_person" => "US citizen or permanent resident",
            "resident"  => "Resident alien (substantial presence)"
          })
          transition to: :prior_return_available
        end

        ask :prior_return_available do
          type :enum
          question "Do you have a copy of your most recent tax return?"
          options({ "yes_last_year" => "Yes, last year's return", "no" => "No" })
          transition to: :income_types
        end

        ask :income_types do
          type :multi_enum
          question "Select every type of income."
          options({ "W2" => "W-2 wages", "crypto" => "Cryptocurrency" })
          transition to: :done
        end

        say :done do
          text "Thanks."
        end
      end
    end

    it "skips a prefilled single-select question even without skip_if" do
      engine.prefill!(residency_status: "us_person")
      expect(engine.current_step_id).to eq(:prior_return_available)
      expect(engine.answers[:residency_status]).to eq("us_person")
    end

    it "stops on the first question the extraction left unknown" do
      engine.prefill!(residency_status: "us_person", income_types: ["W2"])
      expect(engine.current_step_id).to eq(:prior_return_available)
    end

    it "never re-asks an answered question when reached via a later answer" do
      engine.prefill!(prior_return_available: "yes_last_year")
      expect(engine.current_step_id).to eq(:residency_status)
      engine.answer("us_person")
      expect(engine.current_step_id).to eq(:income_types)
    end
  end

  # Regression: extracted values must be matched against option form VALUES,
  # never displayed labels — and near-misses canonicalize to the value.
  context "when canonicalizing prefilled values against options" do
    let(:definition) do
      Inquirex.define id: "canonical-demo" do
        start :residency_status

        ask :residency_status do
          type :enum
          question "Residency?"
          options({
            "us_person" => "US citizen or permanent resident",
            "resident"  => "Resident alien (substantial presence)"
          })
          transition to: :income_types
        end

        ask :income_types do
          type :multi_enum
          question "Income types?"
          options({ "W2" => "W-2 wages", "crypto" => "Cryptocurrency" })
          transition to: :done
        end

        say :done do
          text "Thanks."
        end
      end
    end

    it "keeps an exact form-value match" do
      engine.prefill!(residency_status: "us_person")
      expect(engine.answers[:residency_status]).to eq("us_person")
    end

    it "canonicalizes a case variant to the form value" do
      engine.prefill!(residency_status: "US_PERSON")
      expect(engine.answers[:residency_status]).to eq("us_person")
    end

    it "canonicalizes a display label to the form value" do
      engine.prefill!(residency_status: "US citizen or permanent resident")
      expect(engine.answers[:residency_status]).to eq("us_person")
    end

    it "drops a value that matches neither value nor label, and still asks" do
      engine.prefill!(residency_status: "alien overlord")
      expect(engine.answers).not_to have_key(:residency_status)
      expect(engine.current_step_id).to eq(:residency_status)
    end

    it "canonicalizes multi-select suggestions entry by entry" do
      engine.prefill!(residency_status: "us_person",
        income_types: ["W-2 wages", "CRYPTO", "bitcoin mining"])
      expect(engine.suggestion_for(:income_types)).to eq(%w[W2 crypto])
    end

    it "records no suggestion when every entry is junk" do
      engine.prefill!(income_types: ["bitcoin mining"])
      expect(engine.suggestion_for(:income_types)).to be_nil
    end

    it "stores schema-only keys (no matching step) verbatim" do
      engine.prefill!(confidence: 0.87)
      expect(engine.answers[:confidence]).to eq(0.87)
    end
  end

  # Prefilled answers must feed accumulators exactly like typed answers —
  # a skipped-because-extracted step still contributes to pricing.
  context "when a prefilled answer feeds an accumulator" do
    let(:definition) do
      Inquirex.define id: "prefill-price-demo" do
        accumulator :price, default: 0

        start :filing_status

        ask :filing_status do
          type :enum
          question "Filing status?"
          options({ "single" => "Single", "married" => "Married" })
          price lookup: { "single" => 100, "married" => 150 }
          transition to: :done
        end

        say :done do
          text "Thanks."
        end
      end
    end

    it "applies the accumulation when the value prefills" do
      engine.prefill!(filing_status: "Married")
      expect(engine.answers[:filing_status]).to eq("married")
      expect(engine.total(:price)).to eq(150)
      expect(engine.current_step_id).to eq(:done)
    end
  end
end
