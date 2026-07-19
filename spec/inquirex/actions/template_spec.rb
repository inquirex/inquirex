# frozen_string_literal: true

RSpec.describe Inquirex::Actions::Template do
  subject(:answers) do
    Inquirex::Answers.new(
      name:         "Ada & Co",
      email:        "ada@lovelace.io",
      income_types: %w[W2 Business],
      business:     { count: 3 }
    )
  end

  describe ".render_text" do
    it { expect(described_class.render_text("Hi {{name}}!", answers)).to eq("Hi Ada & Co!") }
    it { expect(described_class.render_text("{{ email }}", answers)).to eq("ada@lovelace.io") }
    it { expect(described_class.render_text("{{business.count}}", answers)).to eq("3") }
    it { expect(described_class.render_text("{{income_types}}", answers)).to eq("W2, Business") }
    it { expect(described_class.render_text("{{missing}}", answers)).to eq("") }
    it { expect(described_class.render_text("no placeholders", answers)).to eq("no placeholders") }

    it "expands {{answers_summary}} as key: value lines" do
      summary = described_class.render_text("{{answers_summary}}", answers)
      expect(summary.lines.map(&:chomp))
        .to include("name: Ada & Co", "business.count: 3", "income_types: W2, Business")
    end
  end

  describe ".render_html" do
    it "escapes interpolated values but not the template itself" do
      html = described_class.render_html("<p>Hi {{name}} & co</p>", answers)
      expect(html).to eq("<p>Hi Ada &amp; Co & co</p>")
    end

    it "expands {{answers_summary}} as an escaped table" do
      html = described_class.render_html("{{answers_summary}}", answers)
      expect(html).to start_with(%(<table class="inquirex-answers">))
      expect(html).to include("<th>name</th><td>Ada &amp; Co</td>")
    end
  end
end
