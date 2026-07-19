# frozen_string_literal: true

require "tmpdir"

RSpec.describe Inquirex::Actions::SendEmail do
  subject(:effect) do
    described_class.new(
      to:      "{{email}}",
      from:    "forms@agentica.group",
      subject: "Thanks {{name}}!",
      text:    "Hi {{name}}\n{{answers_summary}}",
      html:    "<p>Hi {{name}}</p>{{answers_summary}}"
    )
  end

  let(:answers) { Inquirex::Answers.new(name: "Ada & Co", email: "ada@lovelace.io") }

  it { is_expected.to be_serializable }
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
        .to raise_error(Inquirex::Errors::DefinitionError, /text: or html: body/)
    end

    it "rejects non-template bodies" do
      expect { described_class.new(to: "a@b.c", subject: "s", text: 42) }
        .to raise_error(Inquirex::Errors::DefinitionError, /template String/)
    end
  end

  describe "#to_mail" do
    subject(:mail) { effect.to_mail(answers) }

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
        path = File.join(dir, "body.txt")
        File.write(path, "Hello {{name}}")
        effect = described_class.new(to: "a@b.c", subject: "s", text: { file: path })
        expect(effect.text).to eq("Hello {{name}}")
      end
    end
  end

  describe "serialization round-trip" do
    subject(:restored) { described_class.from_h(effect.to_h) }

    its(:to_h) { is_expected.to eq(effect.to_h) }

    it "builds an equivalent mail" do
      expect(restored.to_mail(answers).subject).to eq("Thanks Ada & Co!")
    end
  end
end
