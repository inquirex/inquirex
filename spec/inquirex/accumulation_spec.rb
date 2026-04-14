# frozen_string_literal: true

RSpec.describe Inquirex::Accumulation do
  describe ":lookup shape" do
    subject(:accumulation) do
      described_class.new(target: :price,
        shape: :lookup,
        payload: { "single" => 200, "mfj" => 400 })
    end

    it "returns the amount matching the answer" do
      expect(accumulation.contribution("single")).to eq(200)
      expect(accumulation.contribution("mfj")).to eq(400)
    end

    it "returns 0 for unknown answers" do
      expect(accumulation.contribution("unknown")).to eq(0)
    end

    it "returns 0 for nil answer" do
      expect(accumulation.contribution(nil)).to eq(0)
    end

    it "coerces symbol answers to strings" do
      expect(accumulation.contribution(:single)).to eq(200)
    end
  end

  describe ":per_unit shape" do
    subject(:accumulation) do
      described_class.new(target: :price, shape: :per_unit, payload: 25)
    end

    it "multiplies rate by the numeric answer" do
      expect(accumulation.contribution(4)).to eq(100)
    end

    it "parses stringy numbers" do
      expect(accumulation.contribution("3")).to eq(75)
    end

    it "returns 0 for non-numeric answers" do
      expect(accumulation.contribution("banana")).to eq(0)
    end
  end

  describe ":per_selection shape" do
    subject(:accumulation) do
      described_class.new(target: :price,
        shape: :per_selection,
        payload: { "c" => 150, "e" => 75, "d" => 50 })
    end

    it "sums the amounts for selected options" do
      expect(accumulation.contribution(%w[c e])).to eq(225)
    end

    it "ignores unknown selections" do
      expect(accumulation.contribution(%w[c zzz])).to eq(150)
    end

    it "returns 0 for non-array answers" do
      expect(accumulation.contribution("c")).to eq(0)
    end
  end

  describe ":flat shape" do
    subject(:accumulation) do
      described_class.new(target: :complexity, shape: :flat, payload: 1)
    end

    it "adds the amount when answer is truthy" do
      expect(accumulation.contribution(true)).to eq(1)
      expect(accumulation.contribution("anything")).to eq(1)
    end

    it "is 0 for false / empty" do
      expect(accumulation.contribution(false)).to eq(0)
      expect(accumulation.contribution("")).to eq(0)
      expect(accumulation.contribution([])).to eq(0)
    end
  end

  describe "JSON serialization" do
    subject(:accumulation) do
      described_class.new(target: :price,
        shape: :lookup,
        payload: { "single" => 200, "mfj" => 400 })
    end

    let(:hash) { accumulation.to_h }
    let(:restored) { described_class.from_h(:price, hash) }

    it { expect(hash).to eq({ "lookup" => { "single" => 200, "mfj" => 400 } }) }
    it { expect(restored.target).to eq(:price) }
    it { expect(restored.shape).to eq(:lookup) }
    it { expect(restored.contribution("mfj")).to eq(400) }
  end

  describe "validation" do
    it "rejects unknown shapes" do
      expect do
        described_class.new(target: :price, shape: :mystery, payload: 1)
      end.to raise_error(Inquirex::Errors::DefinitionError, /Unknown accumulator shape/)
    end
  end
end
