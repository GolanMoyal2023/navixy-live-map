// Production: tunnel exposes https://navixy-livemap.moyals.net -> localhost:8765 only.
// Use one /data URL for both sources so the live map gets correct data.
window.NAVIXY_MAP_DATA_SOURCES = {
  motorized_gse: "https://navixy-livemap.moyals.net/data",
  direct: "https://navixy-livemap.moyals.net/data",
  both: null,
};
