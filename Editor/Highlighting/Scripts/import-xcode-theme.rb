#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "open3"
require "yaml"

ROOT = File.expand_path("../../..", __dir__)
DEFAULT_PALETTE = File.join(ROOT, "Editor/Highlighting/xcode-style-palette.yaml")
DEFAULT_DARK_THEME = File.expand_path("~/Library/Developer/Xcode/UserData/FontAndColorThemes/Default (Dark).xccolortheme")
DEFAULT_LIGHT_THEME = File.expand_path("~/Library/Developer/Xcode/UserData/FontAndColorThemes/Default (Light).xccolortheme")

XCODE_SYNTAX_KEYS = {
  "Plain Text" => "xcode.syntax.plain",
  "Comments" => "xcode.syntax.comment",
  "Documentation Markup" => "xcode.syntax.comment.doc",
  "Documentation Markup Keywords" => "xcode.syntax.comment.doc.keyword",
  "Marks" => "xcode.syntax.mark",
  "Strings" => "xcode.syntax.string",
  "Characters" => "xcode.syntax.character",
  "Numbers" => "xcode.syntax.number",
  "Regex Literals" => "xcode.syntax.regex",
  "Regex Literal Numbers" => "xcode.syntax.regex.number",
  "Regex Literal Capture Names" => "xcode.syntax.regex.capturename",
  "Regex Literal Character Class Names" => "xcode.syntax.regex.charname",
  "Regex Literal Operators" => "xcode.syntax.regex.other",
  "Keywords" => "xcode.syntax.keyword",
  "Preprocessor Statements" => "xcode.syntax.preprocessor",
  "URLs" => "xcode.syntax.url",
  "Attributes" => "xcode.syntax.attribute",
  "Type Declarations" => "xcode.syntax.declaration.type",
  "Other Declarations" => "xcode.syntax.declaration.other",
  "Project Class Names" => "xcode.syntax.identifier.class",
  "Project Function and Method Names" => "xcode.syntax.identifier.function",
  "Project Constants" => "xcode.syntax.identifier.constant",
  "Project Type Names" => "xcode.syntax.identifier.type",
  "Project Properties and Globals" => "xcode.syntax.identifier.variable",
  "Project Preprocessor Macros" => "xcode.syntax.identifier.macro",
  "Other Class Names" => "xcode.syntax.identifier.class.system",
  "Other Function Names" => "xcode.syntax.identifier.function.system",
  "Other Method Names" => "xcode.syntax.identifier.function.system",
  "Other Constants" => "xcode.syntax.identifier.constant.system",
  "Other Type Names" => "xcode.syntax.identifier.type.system",
  "Other Properties and Globals" => "xcode.syntax.identifier.variable.system",
  "Other Variables" => "xcode.syntax.identifier.variable.system",
  "Other Parameters" => "xcode.syntax.identifier.variable.system",
  "Other Preprocessor Macros" => "xcode.syntax.identifier.macro.system"
}.freeze

FIELD_ORDER = %w[
  Name
  XcodeCategory
  XcodeSyntax
  ZedStyle
  Supported
  ZedNative
  Needs
  Dark
  Light
  FontSize
  FontWeight
  FontStyle
  TextDecoration
  Notes
].freeze

HEADER = <<~YAML
  # Human-editable Xcode-style palette for Neat.
  #
  # This file is intentionally human-editable. The importer can refresh Xcode-
  # derived color/font fields while preserving Neat support metadata.
  #
  # Style field notes:
  # - XcodeSyntax is the source plist key in Xcode's .xccolortheme files.
  # - ZedStyle is the closest Zed syntax style key we currently emit or want to map to.
  # - Supported means current end-to-end support in the Neat editor pipeline:
  #   true = Tree-sitter/LSP can emit it today and Zed can style it.
  #   partial = some path exists, but it is incomplete or not 1:1 with Xcode.
  #   false = this is design intent only until the listed work is done.
  # - ZedNative means whether Zed has a direct style key/category we can target
  #   without custom Neat semantic token work.
  # - Needs lists the missing Neat-side pieces. Use [] when no known work remains.
  # - FontWeight values to use: normal, medium, semibold, bold.
  # - FontStyle values to use: normal, italic.
  # - TextDecoration values to use: none, underline, strikethrough.
  # - FontSize is included for design intent, but most editors may not support
  #   per-token font sizes safely.
YAML

options = {
  palette: DEFAULT_PALETTE,
  dark: DEFAULT_DARK_THEME,
  light: DEFAULT_LIGHT_THEME
}

OptionParser.new do |parser|
  parser.banner = "Usage: import-xcode-theme.rb [options]"
  parser.on("--palette PATH", "Palette YAML to update") { |path| options[:palette] = path }
  parser.on("--dark PATH", "Dark .xccolortheme file") { |path| options[:dark] = path }
  parser.on("--light PATH", "Light .xccolortheme file") { |path| options[:light] = path }
end.parse!

def load_plist(path)
  stdout, stderr, status = Open3.capture3("plutil", "-convert", "json", "-o", "-", path)
  abort("failed to read #{path}: #{stderr}") unless status.success?

  JSON.parse(stdout)
end

def rgba_to_hex(value)
  components = value.to_s.split.map(&:to_f)
  return nil unless components.length == 4

  channels = components.map do |component|
    scaled = (component * 255).round
    [[scaled, 0].max, 255].min
  end

  "#%02X%02X%02X%02X" % channels
end

def font_style(value)
  font = value.to_s
  weight =
    if font.match?(/bold/i)
      "bold"
    elsif font.match?(/semibold/i)
      "semibold"
    elsif font.match?(/medium/i)
      "medium"
    else
      "normal"
    end

  style = font.match?(/italic/i) ? "italic" : "normal"
  size = font[/ - ([0-9]+(?:\.[0-9]+)?)$/, 1]
  size = size.to_f.then { |number| number == number.to_i ? number.to_i : number } if size

  [size, weight, style]
end

def syntax_colors(theme)
  theme.fetch("DVTSourceTextSyntaxColors", {})
end

def syntax_fonts(theme)
  theme.fetch("DVTSourceTextSyntaxFonts", {})
end

def yaml_scalar(value)
  case value
  when true, false
    value.to_s
  when nil
    nil
  when Numeric
    value.to_s
  when Array
    return "[]" if value.empty?
    nil
  else
    value.to_s.inspect
  end
end

def emit_entry(entry)
  lines = []
  FIELD_ORDER.each do |field|
    next unless entry.key?(field)

    value = entry[field]
    if value.nil?
      lines << "  #{field}:"
    elsif (scalar = yaml_scalar(value))
      lines << "  #{field}: #{scalar}"
    elsif value.is_a?(Array)
      lines << "  #{field}:"
      value.each { |item| lines << "    - #{item}" }
    else
      lines << "  #{field}: #{value.inspect}"
    end
  end
  lines
end

palette = YAML.load_file(options[:palette])
dark = load_plist(options[:dark])
light = load_plist(options[:light])

dark_colors = syntax_colors(dark)
light_colors = syntax_colors(light)
dark_fonts = syntax_fonts(dark)
light_fonts = syntax_fonts(light)

updated = 0
palette.each do |entry|
  name = entry.fetch("Name")
  xcode_key = entry["XcodeSyntax"] || XCODE_SYNTAX_KEYS[name]
  next unless xcode_key

  entry["XcodeSyntax"] = xcode_key
  entry["Dark"] = rgba_to_hex(dark_colors[xcode_key]) if dark_colors.key?(xcode_key)
  entry["Light"] = rgba_to_hex(light_colors[xcode_key]) if light_colors.key?(xcode_key)

  font = dark_fonts[xcode_key] || light_fonts[xcode_key]
  if font
    size, weight, style = font_style(font)
    entry["FontSize"] = size
    entry["FontWeight"] = weight
    entry["FontStyle"] = style
  end

  updated += 1
end

body = palette.map { |entry| "- #{emit_entry(entry).join("\n").sub(/^  /, "")}" }.join("\n\n")
File.write(options[:palette], "#{HEADER}\n#{body}\n")
puts "Updated #{updated} palette entries from Xcode themes."
