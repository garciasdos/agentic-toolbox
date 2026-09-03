# frozen_string_literal: true

module NoComments
  module Languages
    module Ruby
      NAME = "ruby"
      ALIASES = %w[ruby rb].freeze

      PATHS = /\.(?:rb|rake)\z/
      EXCLUDED = %r{/vendor/(?:bundle|gems)/|/db/schema\.rb\z|_pb\.rb\z}
      MARKERS = %w[Gemfile].freeze

      ADVICE = "extract it into a well-named method and let the name carry " \
               "the meaning."

      SHEBANG = /!/
      FROZEN_STRING_LITERAL = /frozen_string_literal\s*:/
      SOURCE_ENCODING = /(?:en)?coding\s*[:=]/
      EMACS_MODELINE = /-\*-/
      SORBET_SIGIL = /typed\s*:/
      RUBOCOP_DIRECTIVE = /rubocop\s*:/
      RDOC_VISIBILITY = /:\s*no(?:doc|cov)\s*:/

      PRAGMA = /\A\#\s*#{Regexp.union(SHEBANG, FROZEN_STRING_LITERAL, SOURCE_ENCODING,
                                      EMACS_MODELINE, SORBET_SIGIL, RUBOCOP_DIRECTIVE,
                                      RDOC_VISIBILITY)}/

      BLOCK_COMMENT_START = "=begin"
      BLOCK_COMMENT_END = "=end"

      HEREDOC_OPENER = /<<([-~])?(["'`]?)([A-Z_][A-Z0-9_]*)\2/

      PERCENT_LITERAL_CLOSERS = { "[" => "]", "(" => ")", "{" => "}", "<" => ">" }.freeze
      PERCENT_LITERAL_OPENER = /\A%[qQwWiIrs]?([^\sA-Za-z0-9])/

      PUNCTUATION_OPENING_EXPRESSION = /[\s(\[{,=]/

      module_function

      def comments(text, _path = "")
        found = []
        heredoc_terminators_awaited = []
        inside_block_comment = false

        text.to_s.each_line do |raw|
          line = raw.chomp

          if heredoc_terminators_awaited.any?
            heredoc_terminators_awaited.shift if line.strip == heredoc_terminators_awaited.first
            next
          end

          if inside_block_comment
            inside_block_comment = false if line.start_with?(BLOCK_COMMENT_END)
            next
          end

          if line.start_with?(BLOCK_COMMENT_START)
            inside_block_comment = true
            found << line
            next
          end

          comment = comment_at(line)
          found << comment.strip if comment && !comment.match?(PRAGMA)

          line.scan(HEREDOC_OPENER) { |_, _, terminator| heredoc_terminators_awaited << terminator }
        end

        found
      end

      def comment_at(line)
        index = 0
        previous = nil

        while index < line.length
          char = line[index]

          case char
          when "'", '"', "`"
            index = skip_string(line, index, char)
            previous = nil
            next
          when "%"
            after_literal = end_of_percent_literal(line, index, previous)
            if after_literal
              index = after_literal
              previous = nil
              next
            end
          when "#"
            return line[index..] if comment_can_start_after?(previous)
          end

          previous = char
          index += 1
        end

        nil
      end

      def comment_can_start_after?(previous)
        previous.nil? || previous.match?(/\s/)
      end

      def end_of_percent_literal(line, start, previous)
        return nil unless opens_expression?(previous)

        opener = line[start..].match(PERCENT_LITERAL_OPENER)
        return nil unless opener

        scan_to_percent_literal_close(line, start + opener[0].length, opener[1])
      end

      def opens_expression?(previous)
        previous.nil? || previous.match?(PUNCTUATION_OPENING_EXPRESSION)
      end

      def scan_to_percent_literal_close(line, start, open)
        close = PERCENT_LITERAL_CLOSERS[open] || open
        nestable = close != open
        depth = 1
        index = start

        while index < line.length
          case line[index]
          when "\\" then index += 1
          when open then depth += 1 if nestable
          when close
            depth -= 1
            return index + 1 if depth.zero?
          end
          index += 1
        end

        index
      end

      def skip_string(line, start, quote)
        index = start + 1

        while index < line.length
          case line[index]
          when "\\"
            index += 2
            next
          when quote
            return index + 1
          when "#"
            if interpolates?(quote) && line[index + 1] == "{"
              index = skip_interpolation(line, index + 2)
              next
            end
          end
          index += 1
        end

        index
      end

      def interpolates?(quote)
        quote != "'"
      end

      def skip_interpolation(line, start)
        depth = 1
        index = start

        while index < line.length && depth.positive?
          case line[index]
          when "{" then depth += 1
          when "}" then depth -= 1
          end
          index += 1
        end

        index
      end
    end
  end
end
