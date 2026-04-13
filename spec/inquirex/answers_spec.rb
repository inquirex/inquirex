# frozen_string_literal: true

RSpec.describe Inquirex::Answers do
  subject(:answers) do
    described_class.new(
      filing_status: "single",
      dependents:    2,
      business:      { count: 3, type: "llc" }
    )
  end

  describe "bracket access" do
    it { expect(answers[:filing_status]).to eq("single") }
    it { expect(answers[:dependents]).to eq(2) }
    it { expect(answers[:missing]).to be_nil }
  end

  describe "dot-notation access" do
    it { expect(answers.filing_status).to eq("single") }
    it { expect(answers.dependents).to eq(2) }

    it "wraps nested hashes" do
      expect(answers.business).to be_a(described_class)
    end

    it { expect(answers.business.count).to eq(3) }
    it { expect(answers.business.type).to eq("llc") }

    it "raises NoMethodError for non-existent keys" do
      expect { answers.nonexistent }.to raise_error(NoMethodError)
    end
  end

  describe "#dig" do
    it { expect(answers.dig("business.count")).to eq(3) }
    it { expect(answers.dig(:business, :type)).to eq("llc") }
    it { expect(answers.dig("missing.key")).to be_nil }
  end

  describe "#to_h" do
    it { expect(answers.to_h[:filing_status]).to eq("single") }
    it { expect(answers.to_h[:business]).to eq({ count: 3, type: "llc" }) }
  end

  describe "#to_flat_h" do
    subject(:flat) { answers.to_flat_h }

    it { expect(flat["filing_status"]).to eq("single") }
    it { expect(flat["dependents"]).to eq(2) }
    it { expect(flat["business.count"]).to eq(3) }
    it { expect(flat["business.type"]).to eq("llc") }
    it { expect(flat).not_to have_key("business") }
  end

  describe "#to_json" do
    it "produces valid JSON" do
      parsed = JSON.parse(answers.to_json)
      expect(parsed["filing_status"]).to eq("single")
      expect(parsed["business"]["count"]).to eq(3)
    end
  end

  describe "#merge" do
    it "returns a new Answers with merged data" do
      merged = answers.merge({ extra: "value" })
      expect(merged.extra).to eq("value")
      expect(merged.filing_status).to eq("single")
    end
  end

  describe "#==" do
    it { expect(answers).to eq(described_class.new(answers.to_h)) }
    it { expect(answers).to eq(answers.to_h) }
    it { expect(answers).not_to eq(described_class.new({})) }
  end

  describe "#empty?" do
    it { expect(described_class.new({})).to be_empty }
    it { expect(answers).not_to be_empty }
  end
end
