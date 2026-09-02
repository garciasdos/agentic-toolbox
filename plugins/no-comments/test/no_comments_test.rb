#!/usr/bin/ruby
# frozen_string_literal: true

# End-to-end tests for the no-comments hook: each case feeds a PreToolUse
# payload on stdin from a fixture project and asserts allow (no output) or deny.
# Stdlib only, like the hook itself: /usr/bin/ruby test/no_comments_test.rb

require "json"
require "open3"
require "tmpdir"

HOOK = File.expand_path("../hooks/no-comments.rb", __dir__)

Case = Struct.new(:name, :expected, :tool_input, :env, :marker, keyword_init: true)

RUBY_CASES = [
  ["narration comment", :deny, { "content" => "x = 1\n# increment the counter\nx += 1\n" }],
  ["clean code", :allow, { "content" => "total = items.sum(&:price)\n" }],
  ["magic comment", :allow, { "content" => "# frozen_string_literal: true\nA = 1\n" }],
  ["shebang", :allow, { "content" => "#!/usr/bin/ruby\nrun\n" }],
  ["rubocop directive", :allow, { "content" => "# rubocop:disable Metrics/AbcSize\ndef f; end\n" }],
  ["sorbet sigil", :allow, { "content" => "# typed: strict\nA = 1\n" }],
  ["hash inside string", :allow, { "content" => "url = \"https://example.com/#anchor\"\n" }],
  ["hash inside interpolation", :allow, { "content" => "puts \"a#{'#{count} # items'}\"\n" }],
  ["percent literal", :allow, { "content" => "TAGS = %w[a#b c#d]\n" }],
  ["heredoc body", :allow, { "content" => "SQL = <<~TEXT\n  select 1 # not a comment\nTEXT\n" }],
  ["block comment", :deny, { "content" => "=begin\n narrate everything\n=end\nrun\n" }],
  ["modulo then comment", :deny, { "content" => "rest = total % count # explain\n" }],
  ["moved comment kept", :allow, { "old_string" => "# why: upstream sends 200 on error\na = 1\n",
                                   "new_string" => "a = 1\n# why: upstream sends 200 on error\n" }],
  ["added comment in edit", :deny, { "old_string" => "a = 1\n", "new_string" => "a = 1\n# bump\nb = 2\n" }]
].freeze

JS_CASES = [
  ["narration comment", :deny, { "content" => "const x = 1\n// increment the counter\nx += 1\n" }],
  ["clean code", :allow, { "content" => "const total = items.reduce(sum, 0)\n" }],
  ["ts directive", :allow, { "content" => "// @ts-expect-error upstream types are wrong\nfoo()\n" }],
  ["eslint directive", :allow, { "content" => "// eslint-disable-next-line no-console\nlog(1)\n" }],
  ["pure annotation", :allow, { "content" => "const f = /* @__PURE__ */ create()\n" }],
  ["source map", :allow, { "content" => "//# sourceMappingURL=a.js.map\n" }],
  ["license banner", :allow, { "content" => "/*! MIT licensed */\nexport const a = 1\n" }],
  ["triple slash reference", :allow, { "content" => "/// <reference types=\"node\" />\n" }],
  ["url inside string", :allow, { "content" => "const url = \"https://example.com/x\"\n" }],
  ["marker inside template", :allow, { "content" => "const q = `select // not a comment ${id}`\n" }],
  ["nested interpolation", :allow, { "content" => "const s = `a${inner(`b${deep(\"c//d\")}`)}e`\n" }],
  ["regex holding slashes", :allow, { "content" => "const re = /https:\\/\\//\nexport default re\n" }],
  ["regex after return", :allow, { "content" => "function f(s) { return /a\\/b/.test(s) }\n" }],
  ["division then comment", :deny, { "content" => "const ratio = total / count\n// explain the ratio\n" }],
  ["jsdoc restating signature", :deny, { "content" => "/**\n * @param id The user id\n */\nexport const get = (id) => id\n" }],
  ["multiline block", :deny, { "content" => "/*\n step one\n step two\n*/\nrun()\n" }],
  ["moved comment kept", :allow, { "old_string" => "// why: upstream sends 200 on error\nconst a = 1\n",
                                   "new_string" => "const a = 1\n// why: upstream sends 200 on error\n" }],
  ["multiedit one offender", :deny, { "edits" => [{ "old_string" => "a", "new_string" => "b" },
                                                  { "old_string" => "c", "new_string" => "d // tweak" }] }]
].freeze

JSX_CASES = [
  ["jsx expression comment", :deny, { "content" => "const v = <div>{/* render the label */}</div>\n" }],
  ["jsx self closing then comment", :deny, { "content" => "const v = <Foo bar={a} />\n// wrap it up\n" }]
].freeze

SCOPE_CASES = [
  ["ruby file in js project", :allow, "/p/a.rb", "package.json", nil],
  ["js file in ruby project", :allow, "/p/a.ts", "Gemfile", nil],
  ["unknown extension", :allow, "/p/a.go", "package.json", nil],
  ["declaration file", :allow, "/p/types.d.ts", "package.json", nil],
  ["vendored js", :allow, "/p/node_modules/x/i.js", "package.json", nil],
  ["vendored gem", :allow, "/p/vendor/bundle/g/a.rb", "Gemfile", nil],
  ["generated schema", :allow, "/p/db/schema.rb", "Gemfile", nil],
  ["scratchpad", :allow, "/private/tmp/x/a.ts", "package.json", nil],
  ["agent config", :allow, "/u/.claude/hooks/a.ts", "package.json", nil],
  ["no project marker", :allow, "/p/a.ts", nil, nil],
  ["deno project", :deny, "/p/a.ts", "deno.json", nil]
].freeze

SELECTION_CASES = [
  ["unset enforces both", :deny, "/p/a.ts", "package.json", nil],
  ["ruby only skips ts", :allow, "/p/a.ts", "package.json", "ruby"],
  ["ts alias enforces ts", :deny, "/p/a.ts", "package.json", "ts"],
  ["list enforces both", :deny, "/p/a.ts", "package.json", "js,ruby"],
  ["all enforces", :deny, "/p/a.ts", "package.json", "all"],
  ["none disables", :allow, "/p/a.ts", "package.json", "none"],
  ["empty disables", :allow, "/p/a.ts", "package.json", ""]
].freeze

def run(tool_input, marker, languages)
  Dir.mktmpdir do |dir|
    File.write(File.join(dir, marker), "{}\n") if marker
    env = languages.nil? ? {} : { "NO_COMMENTS_LANGUAGES" => languages }
    out, = Open3.capture2(env, "/usr/bin/ruby", HOOK,
                          stdin_data: JSON.generate("tool_input" => tool_input),
                          chdir: dir)
    out.strip.empty? ? :allow : :deny
  end
end

def cases_for(group, path, marker)
  group.map do |name, expected, tool_input|
    Case.new(name: name, expected: expected, marker: marker,
             tool_input: tool_input.merge("file_path" => path))
  end
end

def scope_cases(group)
  group.map do |name, expected, path, marker, languages|
    Case.new(name: name, expected: expected, marker: marker, env: languages,
             tool_input: { "file_path" => path, "content" => "// narrate this\n# narrate this\n" })
  end
end

suites = {
  "ruby" => cases_for(RUBY_CASES, "/p/a.rb", "Gemfile"),
  "javascript" => cases_for(JS_CASES, "/p/a.ts", "package.json"),
  "jsx" => cases_for(JSX_CASES, "/p/a.tsx", "package.json"),
  "scope" => scope_cases(SCOPE_CASES),
  "selection" => scope_cases(SELECTION_CASES)
}

failures = 0
total = 0

suites.each do |suite, cases|
  puts "#{suite}:"
  cases.each do |test|
    total += 1
    actual = run(test.tool_input, test.marker, test.env)
    passed = actual == test.expected
    failures += 1 unless passed
    puts format("  %-32s %-5s %s", test.name, actual, passed ? "ok" : "FAIL (expected #{test.expected})")
  end
end

puts
puts failures.zero? ? "#{total} cases pass" : "#{failures} of #{total} FAILING"
exit(failures.zero? ? 0 : 1)
