# frozen_string_literal: true

RSpec.describe Inquirex::TemplateRefs do
  describe ".template?" do
    it { expect(described_class).to be_template("Hi {{ answers.name }}") }
    it { expect(described_class).to be_template("{% if answers.name %}Hi{% endif %}") }
    it { expect(described_class).not_to be_template("Hi there") }
    it { expect(described_class).not_to be_template(nil) }
  end

  describe ".scan" do
    it "reads both drops, in order, without duplicates" do
      source = "Hi {{ answers.name }}, you owe {{ accumulators.price | round: 2 }} — thanks {{answers.name}}"

      expect(described_class.scan(source))
        .to eq([%i[answers name], %i[accumulators price]])
    end

    it "captures only the first path segment of a nested reference" do
      expect(described_class.scan("{{ answers.business.count }}")).to eq([%i[answers business]])
    end

    it "reads whitespace-control markers" do
      expect(described_class.scan("{{- answers.name }}")).to eq([%i[answers name]])
    end

    it "ignores drops it does not know about, rather than guessing" do
      expect(described_class.scan("{{ site.title }} {{ 'x' | upcase }}")).to be_empty
    end

    it { expect(described_class.scan(nil)).to be_empty }
  end

  describe ".warnings" do
    subject(:warnings) { definition.template_warnings }

    context "with a flow whose references all resolve" do
      let(:definition) { Inquirex.load_dsl(DslPayloads.accepted.fetch("liquid in user-facing text")) }

      it { is_expected.to be_empty }
    end

    context "with a flow whose send_email templates all resolve" do
      let(:definition) { Inquirex.load_dsl(DslPayloads.accepted.fetch("send_email declarations")) }

      it { is_expected.to be_empty }
    end

    context "with unresolvable references" do
      let(:definition) do
        Inquirex.load_dsl(<<~RUBY)
          Inquirex.define do
            accumulator :price, type: :currency, default: 0
            start :name

            ask :name do
              type :string
              question "Hi {{ answers.referrer }}, what is your name?"
              transition to: :done
            end

            say :done do
              text "That is ${{ accumulators.total }} — thanks {{ answers.name }}."
            end

            send_email do
              to "{{ answers.phone }}"
              subject "Done"
              body_markdown "Thanks."
            end
          end
        RUBY
      end

      it "names the unknown answer key and where it appears" do
        expect(warnings).to include(
          "step :name question references {{ answers.referrer }}, which no step collects"
        )
      end

      it "names an accumulator the flow never declared" do
        expect(warnings).to include(
          "step :done text references {{ accumulators.total }}, which is not a declared accumulator"
        )
      end

      it "checks send_email templates too, numbered by declaration" do
        expect(warnings).to include(
          "send_email #1 to references {{ answers.phone }}, which no step collects"
        )
      end

      it "says nothing about references that do resolve" do
        expect(warnings.grep(/answers\.name |accumulators\.price /)).to be_empty
      end
    end

    context "with a template using the keys answers_with_metadata merges in" do
      let(:definition) do
        Inquirex.load_dsl(<<~RUBY)
          Inquirex.define do
            start :a

            say :a do
              text "Rendered by {{ answers.completion_metadata }} after {{ answers.skipped }}"
            end
          end
        RUBY
      end

      it { is_expected.to be_empty }
    end
  end
end
