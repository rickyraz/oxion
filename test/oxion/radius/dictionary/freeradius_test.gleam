import gleam/string
import oxion/radius/dictionary/freeradius

pub fn freeradius_dictionary_deduplicates_logical_vendor_attrs_test() {
  let rendered = freeradius.render_default_dictionary()

  assert string.contains(rendered, "VENDOR Cisco 9")
  assert string.contains(rendered, "BEGIN-VENDOR Cisco")
  assert string.contains(rendered, "ATTRIBUTE Cisco-AVPair 1 string")
  assert string.contains(rendered, "END-VENDOR Cisco")
  assert string.contains(rendered, "VENDOR Juniper 2636")
  assert string.contains(
    rendered,
    "ATTRIBUTE ERX-Dynamic-Profile-Name 1 string",
  )
}

pub fn freeradius_dictionary_keeps_standard_attribute_codes_test() {
  let rendered = freeradius.render_default_dictionary()

  assert string.contains(rendered, "ATTRIBUTE User-Name 1 string")
  assert string.contains(rendered, "ATTRIBUTE Class 25 string")
  assert string.contains(rendered, "ATTRIBUTE Message-Authenticator 80 octets")
}
