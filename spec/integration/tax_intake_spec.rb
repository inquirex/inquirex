# frozen_string_literal: true

# Full tax intake flow exercising all rule types, branching, and JSON round-trip.
TAX_INTAKE = Inquirex.define id: "tax-intake-2025", version: "1.0.0" do
  meta title: "Tax Preparation Intake",
    subtitle: "Let's understand your tax situation",
    brand: { name: "Agentica", color: "#2563eb" }

  start :filing_status

  ask :filing_status do
    type :enum
    question "What is your filing status for 2025?"
    options single: "Single",
      married_jointly: "Married Filing Jointly",
      married_separately: "Married Filing Separately",
      head_of_household: "Head of Household"
    transition to: :dependents
  end

  ask :dependents do
    type :integer
    question "How many dependents do you have?"
    default 0
    transition to: :income_types
  end

  ask :income_types do
    type :multi_enum
    question "Select all income types that apply to you in 2025."
    options %w[W2 1099 Business Investment Rental Retirement]
    transition to: :business_count, if_rule: contains(:income_types, "Business")
    transition to: :investment_details, if_rule: contains(:income_types, "Investment")
    transition to: :rental_details, if_rule: contains(:income_types, "Rental")
    transition to: :state_filing
  end

  ask :business_count do
    type :integer
    question "How many businesses do you own or are a partner in?"
    transition to: :investment_details,
      if_rule: all(
        greater_than(:business_count, 2),
        contains(:income_types, "Investment")
      )
    transition to: :business_details
  end

  ask :business_details do
    type :string
    question "Briefly describe your business entities."
    transition to: :investment_details, if_rule: contains(:income_types, "Investment")
    transition to: :rental_details, if_rule: contains(:income_types, "Rental")
    transition to: :state_filing
  end

  ask :investment_details do
    type :multi_enum
    question "What types of investments do you hold?"
    options %w[Stocks Bonds Crypto RealEstate MutualFunds]
    transition to: :rental_details, if_rule: contains(:income_types, "Rental")
    transition to: :state_filing
  end

  ask :rental_details do
    type :integer
    question "How many rental properties do you own?"
    transition to: :state_filing
  end

  ask :state_filing do
    type :multi_enum
    question "Which states do you need to file in?"
    options %w[California NewYork Texas Florida Illinois Other]
    transition to: :foreign_accounts
  end

  confirm :foreign_accounts do
    question "Do you have any foreign financial accounts?"
    transition to: :foreign_account_count, if_rule: equals(:foreign_accounts, true)
    transition to: :deduction_types
  end

  ask :foreign_account_count do
    type :integer
    question "How many foreign accounts do you have?"
    transition to: :deduction_types
  end

  ask :deduction_types do
    type :multi_enum
    question "Which additional deductions apply to you?"
    options %w[Medical Charitable Education Mortgage None]
    transition to: :charitable_amount, if_rule: contains(:deduction_types, "Charitable")
    transition to: :contact_info
  end

  ask :charitable_amount do
    type :currency
    question "What is your total estimated charitable contribution amount for 2025?"
    transition to: :contact_info
  end

  ask :contact_info do
    type :email
    question "What is your email address?"
    transition to: :review
  end

  say :review do
    text "Thank you! We have collected all necessary information."
  end
end

RSpec.describe "Tax Intake integration" do
  subject(:engine) { Inquirex::Engine.new(TAX_INTAKE) }

  describe "simple W2 path" do
    it "walks the short path without branching" do
      engine.answer("single")                             # filing_status
      engine.answer(0)                                    # dependents
      engine.answer(%w[W2])                               # income_types → state_filing
      expect(engine.current_step_id).to eq(:state_filing)
      engine.answer(["California"])                       # state_filing
      engine.answer(false)                                # foreign_accounts → deduction_types
      engine.answer(%w[None])                             # deduction_types → contact_info
      engine.answer("alice@example.com")                  # contact_info
      engine.advance                                      # REVIEW: (say step)
      expect(engine).to be_finished
    end
  end

  describe "complex business path" do
    it "routes through business, investment, and rental steps" do
      engine.answer("married_jointly")                    # filing_status
      engine.answer(2)                                    # dependents
      engine.answer(%w[Business Investment Rental])       # income_types → business_count
      expect(engine.current_step_id).to eq(:business_count)
      engine.answer(1)                                    # business_count → business_details
      engine.answer("LLC selling SaaS products")          # business_details → investment_details
      expect(engine.current_step_id).to eq(:investment_details)
      engine.answer(%w[Stocks Crypto])                    # investment_details → rental_details
      expect(engine.current_step_id).to eq(:rental_details)
      engine.answer(2)                                    # rental_details → state_filing
    end
  end

  describe "JSON round-trip preserves flow behavior" do
    it "round-trips the definition and produces identical navigation" do
      json = TAX_INTAKE.to_json
      restored = Inquirex::Definition.from_json(json)
      engine2 = Inquirex::Engine.new(restored)

      engine.answer("single")
      engine2.answer("single")
      expect(engine2.current_step_id).to eq(engine.current_step_id)

      engine.answer(0)
      engine2.answer(0)

      engine.answer(%w[W2])
      engine2.answer(%w[W2])
      expect(engine2.current_step_id).to eq(engine.current_step_id)
    end
  end
end
