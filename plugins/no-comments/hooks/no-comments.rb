#!/usr/bin/ruby
# frozen_string_literal: true

# PreToolUse hook on Write|Edit|MultiEdit. Denies a write when the text being
# ADDED to a source file contains a comment that is not a machine-read pragma.
# The premise: code states what it does, and a comment restating it rots the
# moment either one changes.
#
# Only ADDED comments count. A comment already present in old_string travels
# with the code it annotates, so refactors and moves never trip the hook.
#
# The file's extension picks the language; each language under languages/ owns
# what is specific to it. README.md documents the contract.
#
# Pinned to /usr/bin/ruby (system ruby, no version-manager shim) and
# stdlib-only. Fail-open everywhere: anything unexpected -> exit 0. Workflow
# guardrail, not a security boundary.

require "json"
require_relative "languages/javascript"
require_relative "languages/ruby"

module NoComments
  LANGUAGES = [Languages::Ruby, Languages::JavaScript].freeze

  IGNORED_PATHS = %r{\A/(?:private/)?tmp/|\.claude/}

  MESSAGE_HEAD = "This codebase carries no explanatory comments: the target " \
                 "is zero. Code states what it does, and a comment restating " \
                 "it rots as soon as either changes. Re-issue the edit " \
                 "without them. When a block reads as though it needs a " \
                 "narration comment, that is a naming problem: "

  MESSAGE_TAIL = " Ticket references belong in the commit message and the " \
                 "PR. If you believe a specific comment is genuinely " \
                 "required (an external quirk or a constraint the code truly " \
                 "cannot express), stop and ask the user to approve that one " \
                 "line rather than writing it."

  module_function

  # Unset enforces every language the plugin ships. A value selects by name or
  # alias ("ruby", "ts", "js,ruby"); "all" is every language and an empty value
  # or "none" disables the hook, which is how a project opts out through the
  # env block of its own .claude/settings.json.
  def enabled_languages
    requested = ENV["NO_COMMENTS_LANGUAGES"]
    return LANGUAGES if requested.nil?

    names = requested.downcase.split(/[,\s]+/).reject(&:empty?)
    return LANGUAGES if names.include?("all")
    return [] if names.empty? || names.include?("none")

    LANGUAGES.select { |language| (language::ALIASES & names).any? }
  end

  def language_for(file)
    enabled_languages.find do |language|
      file.match?(language::PATHS) && !file.match?(language::EXCLUDED)
    end
  end

  def project?(language)
    language::MARKERS.any? { |marker| File.exist?(marker) }
  end

  def added_comments(language, tool_input)
    edits = tool_input["edits"] || [tool_input]
    path = tool_input["file_path"].to_s

    edits.flat_map do |edit|
      new_text = (edit["content"] || edit["new_string"]).to_s
      kept = language.comments(edit["old_string"], path)
      language.comments(new_text, path) - kept
    end
  end

  def report(file, added, language)
    shown = added.first(3).map { |comment| "  #{comment}" }.join("\n")
    more = added.length > 3 ? "\n  (+#{added.length - 3} more)" : ""

    "COMMENT_NOISE: this change adds #{added.length} " \
      "comment#{"s" if added.length > 1} to #{File.basename(file)}:\n" \
      "#{shown}#{more}\n#{MESSAGE_HEAD}#{language::ADVICE}#{MESSAGE_TAIL}"
  end

  def deny(reason)
    puts JSON.generate(
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: reason
      }
    )
    exit 0
  end
end

begin
  input = JSON.parse($stdin.read)

  file = input.dig("tool_input", "file_path").to_s
  exit 0 if file.empty? || file.match?(NoComments::IGNORED_PATHS)

  language = NoComments.language_for(file)
  exit 0 if language.nil?

  # Only guard real projects of that language: plugin hooks run user-globally,
  # and this rule must not fire while editing fixtures or examples in repos
  # that are not written in it.
  exit 0 unless NoComments.project?(language)

  added = NoComments.added_comments(language, input["tool_input"])
  exit 0 if added.empty?

  NoComments.deny(NoComments.report(file, added, language))
rescue StandardError
  exit 0
end
