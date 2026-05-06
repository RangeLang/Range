#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "optparse"
require "yaml"

ROOT = File.expand_path("../../..", __dir__)
DEFAULT_PALETTE = File.join(ROOT, "Editor/Highlighting/xcode-style-palette.yaml")
DEFAULT_SEMANTIC_RULES = File.join(ROOT, "Editor/Highlighting/semantic_token_rules.zed.json")
DEFAULT_BASE_THEME = File.join(ROOT, "Editor/Highlighting/zed-one-base.json")
DEFAULT_OUTPUT = File.join(ROOT, "Zed/Neat/themes/neat-xcode.json")

THEME_NAMES = {
  "dark" => "Neat Xcode Dark",
  "light" => "Neat Xcode Light"
}.freeze

FONT_WEIGHTS = {
  "normal" => 400,
  "medium" => 500,
  "semibold" => 600,
  "bold" => 700
}.freeze

FALLBACK_SCOPE_ALIASES = {
  "keyword" => %w[keyword.control],
  "number" => %w[number.float],
  "string" => %w[string.escape],
  "variable.parameter" => %w[variable.parameter.reference],
  "function.macro" => %w[main]
}.freeze

options = {
  palette: DEFAULT_PALETTE,
  semantic_rules: DEFAULT_SEMANTIC_RULES,
  base_theme: DEFAULT_BASE_THEME,
  output: DEFAULT_OUTPUT
}

OptionParser.new do |parser|
  parser.banner = "Usage: generate-zed-theme.rb [options]"
  parser.on("--palette PATH", "Palette YAML to read") { |path| options[:palette] = path }
  parser.on("--semantic-rules PATH", "Semantic token rules JSON to read") { |path| options[:semantic_rules] = path }
  parser.on("--base-theme PATH", "Base Zed theme JSON to inherit UI/editor styling from") { |path| options[:base_theme] = path }
  parser.on("--output PATH", "Zed theme JSON to write") { |path| options[:output] = path }
end.parse!

def highlight_style(entry, mode)
  color = entry.fetch(mode == "dark" ? "Dark" : "Light")
  return nil if color.nil? || color.to_s.empty?

  style = { "color" => color }
  font_style = entry["FontStyle"]
  style["font_style"] = font_style if font_style && font_style != "normal"

  font_weight_value = entry["FontWeight"]
  font_weight = if font_weight_value.is_a?(Integer)
    font_weight_value
  elsif font_weight_value.to_s.match?(/\A\d+\z/)
    font_weight_value.to_i
  else
    FONT_WEIGHTS[font_weight_value]
  end
  style["font_weight"] = font_weight if font_weight

  style
end

def add_style(syntax, scope, style)
  return if scope.nil? || scope.empty? || style.nil?

  syntax[scope] ||= style
end

def style_for_scope(scope, palette_by_zed_style, mode)
  entry = palette_by_zed_style[scope]
  return nil unless entry

  highlight_style(entry, mode)
end

palette = YAML.load_file(options[:palette])
semantic_rules = JSON.parse(File.read(options[:semantic_rules]))
base_theme = JSON.parse(File.read(options[:base_theme]))
palette_by_zed_style = palette.each_with_object({}) do |entry, result|
  zed_style = entry["ZedStyle"]
  result[zed_style] ||= entry if zed_style
end

base_by_appearance = base_theme.fetch("themes").each_with_object({}) do |theme, result|
  result[theme.fetch("appearance")] = theme
end

themes = %w[dark light].map do |mode|
  inherited_style = Marshal.load(Marshal.dump(base_by_appearance.fetch(mode).fetch("style")))
  syntax = inherited_style.fetch("syntax", {})
  plain_text_style = style_for_scope("text", palette_by_zed_style, mode)
  inherited_style["editor.foreground"] = plain_text_style["color"] if plain_text_style&.key?("color")

  palette.each do |entry|
    style = highlight_style(entry, mode)
    next unless entry["ZedStyle"] && style

    syntax[entry["ZedStyle"]] = style
    Array(FALLBACK_SCOPE_ALIASES[entry["ZedStyle"]]).each do |scope|
      syntax[scope] = style
    end
  end

  semantic_rules.each do |rule|
    styles = Array(rule["style"])
    base = styles.find { |scope| palette_by_zed_style.key?(scope) }
    semantic_style = style_for_scope(base, palette_by_zed_style, mode)
    styles.each { |scope| add_style(syntax, scope, semantic_style) }
  end

  inherited_style["syntax"] = syntax
  {
    "name" => THEME_NAMES.fetch(mode),
    "appearance" => mode,
    "style" => inherited_style
  }
end

theme = {
  "$schema" => "https://zed.dev/schema/themes/v0.2.0.json",
  "name" => "Neat Xcode",
  "author" => "Neat Team",
  "themes" => themes
}

FileUtils.mkdir_p(File.dirname(options[:output]))
File.write(options[:output], "#{JSON.pretty_generate(theme, max_nesting: false)}\n")
puts "Built #{options[:output]}"
