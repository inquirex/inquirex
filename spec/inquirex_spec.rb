# frozen_string_literal: true

RSpec.describe Inquirex do
  it "has a version number" do
    expect(Inquirex::VERSION).not_to be_nil
  end

  describe ".define" do
    subject(:definition) do
      described_class.define id: "test-flow", version: "1.0.0" do
        meta title: "Test Flow", subtitle: "A simple test"
        start :greeting

        say :greeting do
          text "Welcome! Let's get started."
          transition to: :name
        end

        ask :name do
          type :string
          question "What is your name?"
          transition to: :age
        end

        ask :age do
          type :integer
          question "How old are you?"
          transition to: :has_pets, if_rule: greater_than(:age, 17)
          transition to: :done
        end

        confirm :has_pets do
          question "Do you have pets?"
          transition to: :pet_count, if_rule: equals(:has_pets, true)
          transition to: :done
        end

        ask :pet_count do
          type :integer
          question "How many pets?"
          transition to: :done
        end

        say :done do
          text "Thank you for answering!"
        end
      end
    end

    it { is_expected.to be_a(Inquirex::Definition) }
    its(:id)            { is_expected.to eq("test-flow") }
    its(:version)       { is_expected.to eq("1.0.0") }
    its(:start_step_id) { is_expected.to eq(:greeting) }

    it "has expected steps" do
      expect(definition.step_ids).to contain_exactly(:greeting, :name, :age, :has_pets, :pet_count, :done)
    end

    it "says are display nodes" do
      expect(definition.step(:greeting)).to be_display
    end

    it "asks are collecting nodes" do
      expect(definition.step(:name)).to be_collecting
    end

    it "confirms are collecting nodes" do
      expect(definition.step(:has_pets)).to be_collecting
    end
  end

  describe ".define — error cases" do
    it "raises DefinitionError when no start step is set" do
      expect do
        described_class.define do
          ask :name do
            type :string
            question "Name?"
          end
        end
      end.to raise_error(Inquirex::Errors::DefinitionError, /No start step defined/)
    end

    it "raises DefinitionError when no steps are defined" do
      expect do
        described_class.define do
          start :name
        end
      end.to raise_error(Inquirex::Errors::DefinitionError, /No steps defined/)
    end

    it "raises DefinitionError when start references unknown step" do
      expect do
        described_class.define do
          start :missing
          ask :name do
            type :string
            question "Name?"
          end
        end
      end.to raise_error(Inquirex::Errors::DefinitionError, /not found/)
    end
  end
end
