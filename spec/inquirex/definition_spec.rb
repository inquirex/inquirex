# frozen_string_literal: true

RSpec.describe Inquirex::Definition do
  subject(:definition) do
    Inquirex.define id: "tax-2025", version: "2.0.0" do
      meta title: "Tax Intake", subtitle: "Quick and painless", brand: { name: "Acme", color: "#2563eb" }
      start :filing_status

      ask :filing_status do
        type :enum
        question "What is your filing status?"
        options single: "Single", married_jointly: "Married Filing Jointly"
        transition to: :income_types
      end

      ask :income_types do
        type :multi_enum
        question "Select all income types."
        options %w[W2 Business Investment]
        transition to: :business_count, if_rule: contains(:income_types, "Business")
        transition to: :done
      end

      ask :business_count do
        type :integer
        question "How many businesses?"
        transition to: :done
      end

      say :done do
        text "Thanks for completing the intake."
      end
    end
  end

  it { expect(definition).to be_frozen }
  its(:id)            { is_expected.to eq("tax-2025") }
  its(:version)       { is_expected.to eq("2.0.0") }
  its(:start_step_id) { is_expected.to eq(:filing_status) }

  it "has expected step ids" do
    expect(definition.step_ids).to contain_exactly(:filing_status, :income_types, :business_count, :done)
  end

  describe "#step" do
    it { expect(definition.step(:filing_status)).to be_a(Inquirex::Node) }

    it "raises UnknownStepError for missing step" do
      expect { definition.step(:missing) }.to raise_error(Inquirex::Errors::UnknownStepError)
    end
  end

  describe "JSON round-trip" do
    let(:json) { definition.to_json }
    let(:restored) { described_class.from_json(json) }

    it "produces valid JSON" do
      expect { JSON.parse(json) }.not_to raise_error
    end

    it { expect(json).to include('"id":"tax-2025"') }
    it { expect(json).to include('"start":"filing_status"') }

    it "restores id and version" do
      expect(restored.id).to eq("tax-2025")
      expect(restored.version).to eq("2.0.0")
    end

    it "restores start_step_id" do
      expect(restored.start_step_id).to eq(:filing_status)
    end

    it "restores all steps" do
      expect(restored.step_ids).to contain_exactly(:filing_status, :income_types, :business_count, :done)
    end

    it "restores transitions with rules" do
      income = restored.step(:income_types)
      expect(income.transitions.size).to eq(2)
      rule = income.transitions.first.rule
      expect(rule).to be_a(Inquirex::Rules::Contains)
      expect(rule.field).to eq(:income_types)
      expect(rule.value).to eq("Business")
    end

    it "restores option labels" do
      filing = restored.step(:filing_status)
      expect(filing.options).to eq(%w[single married_jointly])
      expect(filing.option_labels["single"]).to eq("Single")
    end

    it "restores meta" do
      expect(restored.meta["title"]).to eq("Tax Intake")
      expect(restored.meta["brand"]["color"]).to eq("#2563eb")
    end

    it "restores say node as display verb" do
      expect(restored.step(:done)).to be_display
    end
  end

  describe "meta theme support" do
    subject(:themed) do
      Inquirex.define id: "themed" do
        meta title: "T",
          brand: { name: "Acme", logo: "https://cdn/logo.png" },
          theme: { brand: "#2563eb", on_brand: "#fff", radius: "18px", header_font: "Inter" }
        start :q
        ask :q do
          type :string
          question "?"
          transition to: :q
        end
      end
    end

    it "carries the theme in meta" do
      expect(themed.meta[:theme]).to include(brand: "#2563eb", radius: "18px")
    end

    it "converts snake_case keys to camelCase for the JS widget" do
      expect(themed.meta[:theme]).to include(onBrand: "#fff", headerFont: "Inter")
      expect(themed.meta[:theme]).not_to have_key(:on_brand)
    end

    it "survives JSON round-trip" do
      restored = described_class.from_json(themed.to_json)
      expect(restored.meta["theme"]["brand"]).to eq("#2563eb")
      expect(restored.meta["theme"]["onBrand"]).to eq("#fff")
      expect(restored.meta["brand"]["logo"]).to eq("https://cdn/logo.png")
    end
  end

  describe ".from_json with invalid JSON" do
    it "raises SerializationError" do
      expect do
        described_class.from_json("not json{{{")
      end.to raise_error(Inquirex::Errors::SerializationError)
    end
  end
end
