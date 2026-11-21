/// The extra fields a donghua detail page shows beyond a western series.
class DonghuaDetails {
  const DonghuaDetails({
    this.studio,
    this.year,
    this.status,
    this.episodeCount,
    this.country,
  });

  final String? studio;
  final int? year;
  final String? status;
  final int? episodeCount;
  final String? country;

  bool get isEmpty =>
      studio == null &&
      year == null &&
      status == null &&
      episodeCount == null &&
      country == null;

  static DonghuaDetails fromTmdb(Map<String, dynamic> json) {
    final companies = json['production_companies'];
    String? studio;
    if (companies is List) {
      for (final company in companies) {
        if (company is Map && company['name'] is String) {
          studio = company['name'] as String;
          break;
        }
      }
    }
    final countries = json['production_countries'];
    String? country;
    if (countries is List) {
      for (final entry in countries) {
        if (entry is Map && entry['iso_3166_1'] is String) {
          country = entry['iso_3166_1'] as String;
          break;
        }
      }
    }
    final year = int.tryParse(
      (json['first_air_date'] ?? json['release_date'] ?? '').toString().split('-').first,
    );
    return DonghuaDetails(
      studio: studio,
      year: year,
      status: json['status'] as String?,
      episodeCount: json['number_of_episodes'] is num
          ? (json['number_of_episodes'] as num).toInt()
          : null,
      country: country,
    );
  }
}
