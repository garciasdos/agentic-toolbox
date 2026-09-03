# frozen_string_literal: true

# JavaScript/TypeScript scanner for the no-comments hook.
#
# The scanner is a state machine over the source: single/double quoted strings,
# template literals with ${} interpolation, and regex literals are skipped so a
# '//' inside data is not read as a comment. Division and regex are told apart
# by the preceding significant token, which keeps 'total / count' and JSX '/>'
# out of it. Ambiguity resolves toward silence: a missed comment is a review
# finding, a false deny is a blocked agent.

module NoComments
  module Languages
    module JavaScript
      NAME = "javascript"
      ALIASES = %w[javascript js jsx typescript ts tsx node].freeze

      PATHS = /\.(?:[cm]?js|[cm]?ts|jsx|tsx)\z/
      EXCLUDED = %r{
        /(?:node_modules|dist|build|out|coverage|\.next|\.nuxt|__generated__)/ |
        \.d\.[cm]?ts\z                                                        |
        \.min\.js\z                                                           |
        \.generated\.[cm]?[jt]sx?\z
      }x

      TYPESCRIPT_PATHS = /\.(?:ts|tsx|mts|cts)\z/
      MARKERS = %w[package.json tsconfig.json deno.json deno.jsonc jsr.json].freeze

      ADVICE = "extract it into a well-named function and let the name carry " \
               "the meaning. A JSDoc block restating a signature is the same " \
               "noise twice over: the types already say it."

      LINE_PRAGMA = %r{\A//[/!\#@]?\s*(?:
                         @ts-                          |
                         <reference                    |
                         eslint-                       |
                         biome-ignore                  |
                         oxlint-disable                |
                         deno-lint-ignore              |
                         dprint-ignore                 |
                         tslint:                       |
                         prettier-ignore               |
                         (?:istanbul|c8|v8)\s+ignore   |
                         codecov                       |
                         sourceMappingURL              |
                         @sourceURL                    |
                         @flow                         |
                         \$FlowFixMe                   |
                         @generated                    |
                         @jsx                          |
                         @__PURE__                     |
                         @license                      |
                         @preserve
                       )}x

      BLOCK_PRAGMA = %r{\A/\*[*!]?\s*(?:
                          eslint-                       |
                          eslint-env                    |
                          globals?\s                    |
                          @jsx                          |
                          webpack[A-Za-z]*\s*:          |
                          @vite-ignore                  |
                          \#?__PURE__                   |
                          @__PURE__                     |
                          (?:istanbul|c8|v8)\s+ignore   |
                          prettier-ignore               |
                          @flow                         |
                          @generated                    |
                          @license                      |
                          @preserve
                        )}x

      # A @ts- directive is read by the compiler wherever it sits in the block,
      # including a multiline JSDoc-style one.
      TS_DIRECTIVE = %r{(?:\A|[\s*/])@ts-[a-z-]+}

      # Tags that carry meaning in TypeScript too: @internal drives
      # stripInternal, @deprecated drives editors and lint rules, and
      # @import/@overload/@satisfies feed the checker.
      SEMANTIC_TAGS = /(?:\A|[\s*])@(?:internal|deprecated|import|overload|satisfies)\b/

      # In a .js file JSDoc *is* the type system, so a block carrying any of
      # these is load-bearing and deleting it changes what typechecks. In a
      # .ts file the syntax already says it, and a block restating a typed
      # signature is exactly the noise this hook exists to stop.
      TYPE_TAGS = /(?:\A|[\s*])@(?:type|typedef|callback|param|returns?|template|
                                  enum|this|extends|implements|abstract|readonly|
                                  property|prop|augments|throws|yields|constructor|
                                  namespace)\b/x

      # A '/' can only open a regex in expression position. After these it is
      # an operand, so the '/' divides.
      REGEX_PRECEDING_PUNCTUATION = "(,=:[!&|?{};+-*%~^<>"

      REGEX_PRECEDING_KEYWORDS = %w[
        return typeof case in of new delete void instanceof yield await throw
        else do
      ].freeze

      # Stands in for a skipped literal: a value, so a '/' after it divides.
      VALUE = "\0"

      module_function

      # The path decides whether JSDoc type tags are load-bearing.
      def comments(text, path = "")
        src = text.to_s
        jsdoc_carries_types = !path.to_s.match?(TYPESCRIPT_PATHS)
        found = []
        previous = nil
        index = 0

        while index < src.length
          char = src[index]
          following = src[index + 1]

          if char == "/" && following == "/"
            body, index = read_to_end_of_line(src, index)
            found << flatten(body) unless body.match?(LINE_PRAGMA) || body.match?(TS_DIRECTIVE)
            next
          end

          if char == "/" && following == "*"
            body, index = read_block(src, index)
            found << flatten(body) unless machine_read?(body, jsdoc_carries_types)
            next
          end

          if char == "#" && following == "!" && index.zero?
            _, index = read_to_end_of_line(src, index)
            next
          end

          case char
          when "'", '"'
            index = skip_quoted(src, index, char)
            previous = VALUE
            next
          when "`"
            index = skip_template(src, index)
            previous = VALUE
            next
          when "/"
            after_regex = regex_position?(previous, src, index) ? skip_regex(src, index) : nil
            if after_regex
              index = after_regex
              previous = VALUE
              next
            end
          end

          previous = char unless char.match?(/\s/)
          index += 1
        end

        found
      end

      def machine_read?(body, jsdoc_carries_types)
        return true if body.start_with?("/*!")
        return true if body.match?(BLOCK_PRAGMA)
        return true if body.match?(TS_DIRECTIVE) || body.match?(SEMANTIC_TAGS)

        jsdoc_carries_types && body.match?(TYPE_TAGS)
      end

      def read_to_end_of_line(src, start)
        stop = src.index("\n", start) || src.length
        [src[start...stop], stop]
      end

      def read_block(src, start)
        close = src.index("*/", start + 2)
        stop = close ? close + 2 : src.length
        [src[start...stop], stop]
      end

      def skip_quoted(src, start, quote)
        index = start + 1
        while index < src.length
          case src[index]
          when "\\" then index += 2
          when quote then return index + 1
          when "\n" then return index
          else index += 1
          end
        end
        index
      end

      def skip_template(src, start)
        index = start + 1
        while index < src.length
          case src[index]
          when "\\"
            index += 2
          when "`"
            return index + 1
          when "$"
            index = src[index + 1] == "{" ? skip_interpolation(src, index + 2) : index + 1
          else
            index += 1
          end
        end
        index
      end

      def skip_interpolation(src, start)
        depth = 1
        index = start
        while index < src.length && depth.positive?
          case src[index]
          when "'", '"' then index = skip_quoted(src, index, src[index])
          when "`" then index = skip_template(src, index)
          when "{"
            depth += 1
            index += 1
          when "}"
            depth -= 1
            index += 1
          else index += 1
          end
        end
        index
      end

      # End of a regex literal starting at start, or nil when the '/' turns out
      # to be division: a literal cannot span a line, so an unterminated one is
      # not one.
      def skip_regex(src, start)
        index = start + 1
        in_class = false
        while index < src.length
          case src[index]
          when "\n" then return nil
          when "\\" then index += 2
          when "["
            in_class = true
            index += 1
          when "]"
            in_class = false
            index += 1
          when "/"
            return index + 1 unless in_class

            index += 1
          else index += 1
          end
        end
        nil
      end

      def regex_position?(previous, src, index)
        return true if previous.nil?
        return true if REGEX_PRECEDING_PUNCTUATION.include?(previous)

        word = src[0...index].match(/([A-Za-z_$][A-Za-z0-9_$]*)\s*\z/)
        word ? REGEX_PRECEDING_KEYWORDS.include?(word[1]) : false
      end

      def flatten(body)
        one_line = body.gsub(/\s+/, " ").strip
        one_line.length > 96 ? "#{one_line[0, 96]}…" : one_line
      end
    end
  end
end
