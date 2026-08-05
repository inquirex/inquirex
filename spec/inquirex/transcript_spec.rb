# frozen_string_literal: true

require "rspec/its"

RSpec.describe Inquirex::Transcript do
  let(:definition) do
    Inquirex.define id: "transcript-format" do
      start :filing_status

      ask :filing_status do
        type :enum
        question "What is your filing status?"
        options single: "Single", married_filing_jointly: "Married filing jointly"
        transition to: :income_types
      end

      ask :income_types do
        type :multi_enum
        question "Which income types apply?"
        options W2: "W-2 wages", crypto: "Cryptocurrency"
        transition to: :owns_home
      end

      ask :owns_home do
        type :boolean
        question "Do you own a home?"
        transition to: :intro
      end

      say :intro do
        text "  Depreciation spreads a cost over several years.  "
      end
    end
  end

  let(:node) { definition.step(:filing_status) }

  describe ".display_entry" do
    it "returns the step text, stripped" do
      expect(described_class.display_entry(definition.step(:intro)))
        .to eq("Depreciation spreads a cost over several years.")
    end

    it "returns nil for a step carrying no text" do
      expect(described_class.display_entry(node)).to be_nil
    end
  end

  describe ".answer_entry" do
    it "renders the question and answer as an exchange" do
      expect(described_class.answer_entry(node, "single"))
        .to eq("Q: What is your filing status?\nA: Single")
    end

    it "resolves an option value to the label the user actually saw" do
      expect(described_class.answer_entry(node, "married_filing_jointly"))
        .to eq("Q: What is your filing status?\nA: Married filing jointly")
    end

    it "joins a multi-select answer, labelling each selection" do
      expect(described_class.answer_entry(definition.step(:income_types), %w[W2 crypto]))
        .to eq("Q: Which income types apply?\nA: W-2 wages, Cryptocurrency")
    end

    it "renders booleans as Yes and No, not true and false" do
      home = definition.step(:owns_home)
      expect(described_class.answer_entry(home, true)).to end_with("A: Yes")
      expect(described_class.answer_entry(home, false)).to end_with("A: No")
    end

    it "falls back to the raw value when the step declares no labels" do
      expect(described_class.answer_entry(definition.step(:owns_home), "maybe"))
        .to end_with("A: maybe")
    end

    it "marks an empty answer rather than emitting a blank line" do
      expect(described_class.answer_entry(node, nil)).to end_with("A: (no answer)")
      expect(described_class.answer_entry(definition.step(:income_types), [])).to end_with("A: (no answer)")
    end
  end

  describe ".skipped_entry" do
    it "records that the question was declined" do
      expect(described_class.skipped_entry(node))
        .to eq("Q: What is your filing status?\nA: (skipped)")
    end
  end
end
