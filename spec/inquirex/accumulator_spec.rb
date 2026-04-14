# frozen_string_literal: true

RSpec.describe Inquirex::Accumulator do
  subject(:accumulator) { described_class.new(name: :price, type: :currency, default: 10) }

  its(:name)    { is_expected.to eq(:price) }
  its(:type)    { is_expected.to eq(:currency) }
  its(:default) { is_expected.to eq(10) }
  it            { is_expected.to be_frozen }

  describe "#to_h / .from_h round trip" do
    let(:hash) { accumulator.to_h }
    let(:restored) { described_class.from_h(:price, hash) }

    it { expect(hash).to eq({ "type" => "currency", "default" => 10 }) }
    its([:restored, :name])    { expect(restored.name).to eq(:price) }
    its([:restored, :type])    { expect(restored.type).to eq(:currency) }
    its([:restored, :default]) { expect(restored.default).to eq(10) }
  end
end
