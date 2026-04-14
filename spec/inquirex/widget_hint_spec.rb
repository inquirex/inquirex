# frozen_string_literal: true

RSpec.describe Inquirex::WidgetHint do
  subject(:hint) { described_class.new(type: :radio_group, options: { columns: 2 }) }

  it { is_expected.to be_frozen }
  its(:type)    { is_expected.to eq(:radio_group) }
  its(:options) { is_expected.to eq({ columns: 2 }) }

  describe "#to_h" do
    subject(:hash) { hint.to_h }

    it { is_expected.to eq({ "type" => "radio_group", "columns" => 2 }) }
    it { is_expected.to have_key("type") }

    it "merges options at the top level" do
      expect(hash["columns"]).to eq(2)
    end
  end

  describe ".from_h" do
    it "deserializes from string keys" do
      restored = described_class.from_h({ "type" => "radio_group", "columns" => 2 })
      expect(restored.type).to eq(:radio_group)
      expect(restored.options).to eq({ columns: 2 })
    end

    it "deserializes from symbol keys" do
      restored = described_class.from_h({ type: :dropdown })
      expect(restored.type).to eq(:dropdown)
      expect(restored.options).to be_empty
    end
  end

  describe "round-trip" do
    it "survives to_h -> from_h intact" do
      restored = described_class.from_h(hint.to_h)
      expect(restored.type).to eq(hint.type)
      expect(restored.options).to eq(hint.options)
    end
  end

  describe "no options" do
    subject(:bare) { described_class.new(type: :toggle) }

    its(:to_h) { is_expected.to eq({ "type" => "toggle" }) }
    its(:options) { is_expected.to be_empty }
  end

  describe "string type coercion" do
    it "normalizes type to symbol" do
      expect(described_class.new(type: "dropdown").type).to eq(:dropdown)
    end
  end
end
