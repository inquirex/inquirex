# frozen_string_literal: true

RSpec.describe Inquirex::Rules do
  let(:answers) { { income_types: %w[W2 Business], count: 3, name: "Alice", status: "single" } }

  describe Inquirex::Rules::Contains do
    subject(:rule) { described_class.new(:income_types, "Business") }

    it { is_expected.to be_frozen }
    its(:field) { is_expected.to eq(:income_types) }
    its(:value) { is_expected.to eq("Business") }
    its(:to_s)  { is_expected.to eq("Business in income_types") }

    describe "#evaluate" do
      it { expect(rule.evaluate(answers)).to be true }
      it { expect(rule.evaluate({ income_types: ["W2"] })).to be false }
      it { expect(rule.evaluate({})).to be false }
    end

    describe "#to_h / .from_h" do
      it "round-trips through hash" do
        hash = rule.to_h
        expect(hash).to eq({ "op" => "contains", "field" => "income_types", "value" => "Business" })
        restored = described_class.from_h(hash)
        expect(restored.field).to eq(:income_types)
        expect(restored.value).to eq("Business")
      end
    end
  end

  describe Inquirex::Rules::Equals do
    subject(:rule) { described_class.new(:status, "single") }

    its(:to_s) { is_expected.to eq("status == single") }

    it { expect(rule.evaluate(answers)).to be true }
    it { expect(rule.evaluate({ status: "married" })).to be false }

    it "round-trips through hash" do
      hash = rule.to_h
      expect(hash["op"]).to eq("equals")
      restored = described_class.from_h(hash)
      expect(restored.field).to eq(:status)
    end
  end

  describe Inquirex::Rules::GreaterThan do
    subject(:rule) { described_class.new(:count, 2) }

    its(:to_s) { is_expected.to eq("count > 2") }

    it { expect(rule.evaluate(answers)).to be true }
    it { expect(rule.evaluate({ count: 2 })).to be false }
    it { expect(rule.evaluate({ count: "5" })).to be true }

    it "round-trips through hash" do
      hash = rule.to_h
      restored = described_class.from_h(hash)
      expect(restored.value).to eq(2)
    end
  end

  describe Inquirex::Rules::LessThan do
    subject(:rule) { described_class.new(:count, 5) }

    its(:to_s) { is_expected.to eq("count < 5") }

    it { expect(rule.evaluate(answers)).to be true }
    it { expect(rule.evaluate({ count: 10 })).to be false }
  end

  describe Inquirex::Rules::NotEmpty do
    subject(:rule) { described_class.new(:name) }

    its(:to_s) { is_expected.to eq("name is not empty") }

    it { expect(rule.evaluate(answers)).to be true }
    it { expect(rule.evaluate({ name: nil })).to be false }
    it { expect(rule.evaluate({ name: "" })).to be false }
    it { expect(rule.evaluate({})).to be false }
  end

  describe Inquirex::Rules::All do
    subject(:rule) do
      described_class.new(
        Inquirex::Rules::Contains.new(:income_types, "W2"),
        Inquirex::Rules::GreaterThan.new(:count, 1)
      )
    end

    its(:to_s) { is_expected.to match(/AND/) }

    it { expect(rule.evaluate(answers)).to be true }
    it { expect(rule.evaluate({ income_types: ["W2"], count: 0 })).to be false }

    it "round-trips through hash" do
      hash = rule.to_h
      restored = described_class.from_h(hash)
      expect(restored.rules.size).to eq(2)
      expect(restored.evaluate(answers)).to be true
    end
  end

  describe Inquirex::Rules::Any do
    subject(:rule) do
      described_class.new(
        Inquirex::Rules::Contains.new(:income_types, "Rental"),
        Inquirex::Rules::Contains.new(:income_types, "Business")
      )
    end

    its(:to_s) { is_expected.to match(/OR/) }

    it { expect(rule.evaluate(answers)).to be true }
    it { expect(rule.evaluate({ income_types: ["W2"] })).to be false }
  end

  describe "Inquirex::Rules::Base.from_h" do
    it "deserializes all operators" do
      {
        { "op" => "contains", "field" => "x", "value" => "v" }   => Inquirex::Rules::Contains,
        { "op" => "equals", "field" => "x", "value" => "v" }     => Inquirex::Rules::Equals,
        { "op" => "greater_than", "field" => "x", "value" => 1 } => Inquirex::Rules::GreaterThan,
        { "op" => "less_than", "field" => "x", "value" => 5 }    => Inquirex::Rules::LessThan,
        { "op" => "not_empty", "field" => "x" }                  => Inquirex::Rules::NotEmpty,
        { "op" => "all", "rules" => [] }                         => Inquirex::Rules::All,
        { "op" => "any", "rules" => [] }                         => Inquirex::Rules::Any
      }.each do |hash, klass|
        expect(Inquirex::Rules::Base.from_h(hash)).to be_a(klass)
      end
    end

    it "raises SerializationError for unknown operator" do
      expect do
        Inquirex::Rules::Base.from_h({ "op" => "bogus" })
      end.to raise_error(Inquirex::Errors::SerializationError)
    end
  end
end
