import MotionCore
@testable import MotionEditor
import Testing

@Suite struct StylePropertyTests {
  @Test func searchOnlyReturnsCatalogProperties() {
    #expect(StylePropertyDefinition.matching("BORDER").contains { $0.id == "borderRadius" })
    #expect(StylePropertyDefinition.matching("BORDER").allSatisfy { $0.id.hasPrefix("border") })
    #expect(StylePropertyDefinition.matching("madeUpProperty").isEmpty)
    #expect(StylePropertyDefinition.find("madeUpProperty") == nil)
    #expect(Set(StylePropertyDefinition.all.map(\.id)).count == StylePropertyDefinition.all.count)
  }

  @Test func detectedTypographyAndBordersHaveUsableControls() throws {
    let weight = try #require(StylePropertyDefinition.find("fontWeight"))
    #expect(weight.value(text: "700", unit: "px") == .string("700"))
    let spacing = try #require(StylePropertyDefinition.find("letterSpacing"))
    #expect(spacing.value(text: "-0.5", unit: "px") == .number(-0.5))
    let width = try #require(StylePropertyDefinition.find("borderTopWidth"))
    #expect(width.value(text: "2", unit: "px") == .number(2))
    #expect(width.value(text: "-1", unit: "px") == nil)
    let whitespace = try #require(StylePropertyDefinition.find("whiteSpace"))
    #expect(whitespace.value(text: "pre-wrap", unit: "px") == .string("pre-wrap"))
    #expect(whitespace.value(text: "pre-line", unit: "px") == nil)
  }

  @Test func numericValuesRespectUnitsAndLimits() throws {
    let width = try #require(StylePropertyDefinition.find("width"))
    #expect(width.value(text: "50", unit: "px") == .number(50))
    #expect(width.value(text: "50", unit: "%") == .string("50%"))
    #expect(width.value(text: "nan", unit: "px") == nil)
    let opacity = try #require(StylePropertyDefinition.find("opacity"))
    #expect(opacity.value(text: "0.5", unit: "px") == .number(0.5))
    #expect(opacity.value(text: "1.1", unit: "px") == nil)
    #expect(opacity.value(text: "-1", unit: "px") == nil)
  }

  @Test func optionsAndColorsRejectInvalidValues() throws {
    let position = try #require(StylePropertyDefinition.find("position"))
    #expect(position.value(text: "absolute", unit: "px") == .string("absolute"))
    #expect(position.value(text: "madeUp", unit: "px") == nil)
    let color = try #require(StylePropertyDefinition.find("color"))
    for valid in ["#abc", "#abcd", "#ff0000", "#ff000080", "transparent", "red"] {
      #expect(color.value(text: valid, unit: "px") == .string(valid))
    }
    #expect(color.value(text: "#xyz", unit: "px") == nil)
    #expect(color.value(text: "123456", unit: "px") == nil)
  }
}
