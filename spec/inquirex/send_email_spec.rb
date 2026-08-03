# frozen_string_literal: true

require "tmpdir"

RSpec.describe Inquirex::SendEmail do
  subject(:email) do
    described_class.new(
      to:      "{{email}}",
      from:    "forms@agentica.group",
      subject: "Thanks {{name}}!",
      text:    "Hi {{name}}\n{{answers_summary}}",
      html:    "<p>Hi {{name}}</p>{{answers_summary}}"
    )
  end

  let(:answers) { Inquirex::Answers.new(name: "Ada & Co", email: "ada@lovelace.io") }

  it { is_expected.to be_frozen }

  describe "validation" do
    it "requires to:" do
      expect { described_class.new(to: nil, subject: "s", text: "t") }
        .to raise_error(Inquirex::Errors::DefinitionError, /requires to:/)
    end

    it "requires subject:" do
      expect { described_class.new(to: "a@b.c", subject: " ", text: "t") }
        .to raise_error(Inquirex::Errors::DefinitionError, /requires subject:/)
    end

    it "requires a body" do
      expect { described_class.new(to: "a@b.c", subject: "s") }
        .to raise_error(Inquirex::Errors::DefinitionError, /text:, markdown_text: or html: body/)
    end

    it "rejects non-template bodies" do
      expect { described_class.new(to: "a@b.c", subject: "s", text: 42) }
        .to raise_error(Inquirex::Errors::DefinitionError, /template String/)
    end
  end

  describe "#applicable?" do
    subject(:gated) do
      described_class.new(
        to:      "{{email}}",
        subject: "s",
        text:    "t",
        rule:    Inquirex::Rules::NotEmpty.new(:email)
      )
    end

    it "is true when the rule passes" do
      expect(gated.applicable?(email: "ada@lovelace.io")).to be(true)
    end

    it "is false when the rule fails" do
      expect(gated.applicable?(email: "")).to be(false)
    end

    it "is true when no rule was declared" do
      expect(email.applicable?({})).to be(true)
    end
  end

  describe "#to_mail" do
    subject(:mail) { email.to_mail(answers) }

    its(:to)         { is_expected.to eq(["ada@lovelace.io"]) }
    its(:from)       { is_expected.to eq(["forms@agentica.group"]) }
    its(:subject)    { is_expected.to eq("Thanks Ada & Co!") }
    its(:multipart?) { is_expected.to be(true) }

    it "renders the text part verbatim" do
      expect(mail.text_part.body.to_s).to include("Hi Ada & Co")
    end

    it "HTML-escapes interpolated values in the html part" do
      expect(mail.html_part.body.to_s).to include("<p>Hi Ada &amp; Co</p>")
    end

    context "with only an html body" do
      subject(:mail) do
        described_class.new(to: "a@b.c", subject: "s", html: "<b>{{name}}</b>").to_mail(answers)
      end

      its(:multipart?)   { is_expected.to be(false) }
      its(:content_type) { is_expected.to start_with("text/html") }
      its("body.to_s")   { is_expected.to eq("<b>Ada &amp; Co</b>") }
    end

    context "with only a markdown_text body" do
      subject(:mail) do
        described_class.new(
          to: "a@b.c", subject: "s", markdown_text: "## Hi {{name}}"
        ).to_mail(answers)
      end

      its(:multipart?) { is_expected.to be(false) }

      it "renders the markdown verbatim as the plain-text body" do
        expect(mail.body.to_s).to eq("## Hi Ada & Co")
      end
    end

    context "with custom headers" do
      subject(:mail) do
        described_class.new(
          to:      "a@b.c",
          subject: "s",
          text:    "t",
          headers: { "X-Flow" => "{{name}}" }
        ).to_mail(answers)
      end

      it { expect(mail.header["X-Flow"].value).to eq("Ada & Co") }
    end
  end

  describe "file: bodies" do
    it "reads the template at definition time" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "body.md")
        File.write(path, "Hello {{name}}")
        email = described_class.new(to: "a@b.c", subject: "s", markdown_text: { file: path })
        expect(email.markdown_text).to eq("Hello {{name}}")
      end
    end
  end

  describe "serialization round-trip" do
    subject(:restored) { described_class.from_h(email.to_h) }

    let(:email) do
      described_class.new(
        to:            "{{email}}",
        subject:       "Thanks {{name}}!",
        markdown_text: "Hi {{name}}",
        rule:          Inquirex::Rules::NotEmpty.new(:email)
      )
    end

    its(:to_h) { is_expected.to eq(email.to_h) }

    it "carries the markdown body and the gate rule on the wire" do
      expect(email.to_h).to include(
        "markdown_text" => "Hi {{name}}",
        "if"            => { "op" => "not_empty", "field" => "email" }
      )
    end

    it "rehydrates the gate rule" do
      expect(restored.rule).to be_a(Inquirex::Rules::NotEmpty)
      expect(restored.applicable?(email: "")).to be(false)
    end

    it "builds an equivalent mail" do
      expect(restored.to_mail(answers).subject).to eq("Thanks Ada & Co!")
    end
  end
end
