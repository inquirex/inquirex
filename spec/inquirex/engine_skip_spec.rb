# frozen_string_literal: true

require "rspec/its"

RSpec.describe Inquirex::Engine, "#skip" do
  subject(:engine) { described_class.new(definition) }

  let(:definition) do
    Inquirex.define id: "skip-demo" do
      accumulator :price, type: :currency, default: 0
      start :name

      ask :name do
        type :string
        question "What is your name?"
        transition to: :dependents
      end

      ask :dependents do
        type :integer
        question "How many dependents?"
        required false
        default 2
        price per_unit: 25
        transition to: :kids_notice, if_rule: greater_than(:dependents, 0)
        transition to: :nickname
      end

      say :kids_notice do
        text "Kids are the best."
        transition to: :nickname
      end

      ask :nickname do
        type :string
        question "Any nickname?"
        required false
        transition to: :done
      end

      say :done do
        text "All done."
      end
    end
  end

  describe "Node#required?" do
    it "defaults to true" do
      expect(definition.step(:name)).to be_required
    end

    it "is false when the DSL declares required false" do
      expect(definition.step(:dependents)).not_to be_required
      expect(definition.step(:nickname)).not_to be_required
    end
  end

  describe "guard rails" do
    it "raises RequiredStepError on a required step" do
      expect { engine.skip }.to raise_error(Inquirex::Errors::RequiredStepError, /required/)
    end

    it "raises NonCollectingStepError on a display step" do
      engine.answer("Alice")
      engine.skip # dependents -> default 2 -> kids_notice
      expect { engine.skip }.to raise_error(Inquirex::Errors::NonCollectingStepError)
    end

    it "raises AlreadyFinishedError after the flow ends" do
      engine.answer("Alice")
      engine.skip
      engine.advance # kids_notice
      engine.skip    # nickname
      engine.advance # done
      expect(engine).to be_finished
      expect { engine.skip }.to raise_error(Inquirex::Errors::AlreadyFinishedError)
    end
  end

  describe "skip with a default" do
    before do
      engine.answer("Alice")
      engine.skip
    end

    its(:answers) { is_expected.to include(dependents: 2) }
    its(:skipped) { is_expected.to eq([:dependents]) }

    it "lets the default value drive transition rules" do
      expect(engine.current_step_id).to eq(:kids_notice) # greater_than(:dependents, 0) with default 2
    end

    it "applies accumulations to the default value" do
      expect(engine.total(:price)).to eq(50) # 2 dependents x $25
    end

    it "exposes the predicate for symbols and strings" do
      expect(engine.skipped?(:dependents)).to be(true)
      expect(engine.skipped?("dependents")).to be(true)
      expect(engine.skipped?(:name)).to be(false)
    end
  end

  describe "skip without a default" do
    before do
      engine.answer("Alice")
      engine.skip    # dependents (default 2 -> kids_notice)
      engine.advance # kids_notice
      engine.skip    # nickname, no default
    end

    it "writes no answers entry, not even nil" do
      expect(engine.answers).not_to have_key(:nickname)
    end

    its(:skipped) { is_expected.to eq(%i[dependents nickname]) }

    it "still advances through transitions" do
      expect(engine.current_step_id).to eq(:done)
    end
  end

  describe "state round-trip" do
    before do
      engine.answer("Alice")
      engine.skip
    end

    it "preserves skipped through to_state / from_state" do
      restored = described_class.from_state(definition, engine.to_state)
      expect(restored.skipped).to eq([:dependents])
      expect(restored.skipped?(:dependents)).to be(true)
    end

    it "normalizes string entries from a JSON round-trip back to symbols" do
      state = JSON.parse(engine.to_state.to_json)
      restored = described_class.from_state(definition, state)
      expect(restored.skipped).to eq([:dependents])
      expect(restored.answers).to include(dependents: 2)
      expect(restored.current_step_id).to eq(:kids_notice)
    end
  end

  describe "#answers_with_metadata" do
    it "merges the skipped list under :skipped" do
      engine.answer("Alice")
      engine.skip
      expect(engine.answers_with_metadata[:skipped]).to eq([:dependents])
    end

    it "omits :skipped when nothing was skipped" do
      engine.answer("Alice")
      expect(engine.answers_with_metadata).not_to have_key(:skipped)
    end
  end

  describe "serialization of required" do
    let(:step_hashes) { definition.to_h["steps"] }

    it "emits \"required\": false only for optional steps" do
      expect(step_hashes["dependents"]).to include("required" => false)
      expect(step_hashes["nickname"]).to include("required" => false)
      expect(step_hashes["name"]).not_to have_key("required")
      expect(step_hashes["done"]).not_to have_key("required")
    end

    it "round-trips through to_json / from_json" do
      restored = Inquirex::Definition.from_json(definition.to_json)
      expect(restored.step(:dependents)).not_to be_required
      expect(restored.step(:name)).to be_required
    end

    it "honors required on an engine built from a from_json definition" do
      restored = Inquirex::Definition.from_json(definition.to_json)
      restored_engine = described_class.new(restored)
      expect { restored_engine.skip }.to raise_error(Inquirex::Errors::RequiredStepError)
      restored_engine.answer("Alice")
      restored_engine.skip
      expect(restored_engine.answers).to include(dependents: 2)
      expect(restored_engine.skipped).to eq([:dependents])
    end
  end

  describe "skip with a proc default" do
    let(:definition) do
      Inquirex.define id: "skip-proc-default" do
        start :name

        ask :name do
          type :string
          question "Name?"
          transition to: :greeting
        end

        ask :greeting do
          type :string
          question "Preferred greeting?"
          required false
          default { |answers| "Hello, #{answers[:name]}!" }
          transition to: :done
        end

        say :done do
          text "Done."
        end
      end
    end

    it "resolves the proc against the answers collected so far" do
      engine.answer("Alice")
      engine.skip
      expect(engine.answers[:greeting]).to eq("Hello, Alice!")
      expect(engine.skipped).to eq([:greeting])
    end
  end

  describe "skipping the same step twice (loop)" do
    let(:definition) do
      Inquirex.define id: "skip-loop" do
        start :note

        ask :note do
          type :string
          question "Add a note?"
          required false
          transition to: :more
        end

        ask :more do
          type :string
          question "Another round?"
          transition to: :note, if_rule: equals(:more, "again")
          transition to: :done
        end

        say :done do
          text "Done."
        end
      end
    end

    it "records the step id only once" do
      engine.skip
      engine.answer("again")
      engine.skip
      expect(engine.skipped).to eq([:note])
    end
  end

  describe "interplay with suggestions" do
    let(:definition) do
      Inquirex.define id: "skip-suggestions" do
        start :income_types

        ask :income_types do
          type :multi_enum
          question "Income types?"
          options %w[W2 business rental]
          required false
          transition to: :done
        end

        say :done do
          text "Done."
        end
      end
    end

    it "discards the prefill suggestion for the skipped step" do
      engine.prefill!(income_types: ["business"])
      expect(engine.suggestion_for(:income_types)).to eq(["business"])
      engine.skip
      expect(engine.suggestion_for(:income_types)).to be_nil
      expect(engine.answers).not_to have_key(:income_types)
      expect(engine.skipped).to eq([:income_types])
    end
  end

  describe "skip_if auto-elision vs user skip" do
    let(:definition) do
      Inquirex.define id: "skip-vs-skip-if" do
        start :filing_status

        ask :filing_status do
          type :enum
          question "Filing status?"
          options %w[single married]
          skip_if not_empty(:filing_status)
          default "single"
          required false
          transition to: :done
        end

        say :done do
          text "Done."
        end
      end
    end

    it "does not mark skip_if-elided steps as skipped, nor record their default" do
      engine.prefill!(filing_status: "married")
      expect(engine.current_step_id).to eq(:done)
      expect(engine.skipped).to be_empty
      expect(engine.answers[:filing_status]).to eq("married")
    end
  end
end
