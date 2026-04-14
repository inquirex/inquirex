# frozen_string_literal: true

# Tax-intake pricing flow demonstrating the :price accumulator.
TAX_PRICING = Inquirex.define id: "tax-pricing-2025" do
  meta title: "Tax Preparation Quote"
  start :filing_status

  accumulator :price,      type: :currency, default: 0
  accumulator :complexity, type: :integer,  default: 0

  ask :filing_status do
    type :enum
    question "Filing status?"
    options single: "Single",
      mfj: "Married Filing Jointly",
      hoh: "Head of Household"
    price single: 200, mfj: 400, hoh: 300
    accumulate :complexity, lookup: { mfj: 1 }
    transition to: :dependents
  end

  ask :dependents do
    type :integer
    question "How many dependents?"
    default 0
    price per_unit: 25
    transition to: :schedules
  end

  ask :schedules do
    type :multi_enum
    question "Which schedules apply?"
    options c: "Schedule C (Business)",
      e: "Schedule E (Rental)",
      d: "Schedule D (Capital Gains)"
    price per_selection: { c: 150, e: 75, d: 50 }
    accumulate :complexity, per_selection: { c: 2, e: 1, d: 1 }
    transition to: :done
  end

  say :done do
    text "Thanks! We'll email your quote."
  end
end

RSpec.describe "Pricing integration (accumulators)" do
  subject(:engine) { Inquirex::Engine.new(TAX_PRICING) }

  describe "simple W2 single filer" do
    before do
      engine.answer("single")
      engine.answer(0)
      engine.answer([])
    end

    its(:totals) { is_expected.to eq(price: 200, complexity: 0) }
    it           { expect(engine.total(:price)).to eq(200) }
  end

  describe "MFJ with 3 dependents and 2 schedules" do
    before do
      engine.answer("mfj")
      engine.answer(3)
      engine.answer(%w[c e])
    end

    # 400 base + 3*25 + (150+75) = 700
    it { expect(engine.total(:price)).to eq(700) }
    # mfj=1 + c=2 + e=1 = 4
    it { expect(engine.total(:complexity)).to eq(4) }
  end

  describe "defaults materialize on init" do
    its(:totals) { is_expected.to eq(price: 0, complexity: 0) }
  end

  describe "DSL shorthand: price single: 200, mfj: 400" do
    let(:flow) do
      Inquirex.define id: "sugar" do
        accumulator :price, default: 0
        start :q
        ask :q do
          type :enum
          question "?"
          options a: "A", b: "B"
          price a: 10, b: 20
          transition to: :end
        end
        say :end do
          text "bye"
        end
      end
    end

    it "treats the shorthand hash as a :lookup" do
      e = Inquirex::Engine.new(flow)
      e.answer("b")
      expect(e.total(:price)).to eq(20)
    end
  end

  describe "JSON round-trip preserves accumulators and totals" do
    let(:json) { TAX_PRICING.to_json }
    let(:restored) { Inquirex::Definition.from_json(json) }

    it "serializes the accumulator declarations" do
      parsed = JSON.parse(json)
      expect(parsed["accumulators"]).to eq(
        "price"      => { "type" => "currency", "default" => 0 },
        "complexity" => { "type" => "integer",  "default" => 0 }
      )
    end

    it "serializes step accumulate blocks" do
      parsed = JSON.parse(json)
      expect(parsed["steps"]["filing_status"]["accumulate"]).to eq(
        "price"      => { "lookup" => { "single" => 200, "mfj" => 400, "hoh" => 300 } },
        "complexity" => { "lookup" => { "mfj" => 1 } }
      )
      expect(parsed["steps"]["dependents"]["accumulate"]).to eq(
        "price" => { "per_unit" => 25 }
      )
      expect(parsed["steps"]["schedules"]["accumulate"]).to eq(
        "price"      => { "per_selection" => { "c" => 150, "e" => 75, "d" => 50 } },
        "complexity" => { "per_selection" => { "c" => 2, "e" => 1, "d" => 1 } }
      )
    end

    it "restored engine produces identical totals" do
      e = Inquirex::Engine.new(restored)
      e.answer("mfj")
      e.answer(3)
      e.answer(%w[c e])
      expect(e.total(:price)).to eq(700)
      expect(e.total(:complexity)).to eq(4)
    end
  end
end
