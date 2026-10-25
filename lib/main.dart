import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

const alarmChannel = MethodChannel('com.example.radyo_alarm/alarm');
const accent = Color(0xFFFFC857);
const background = Color(0xFF0B0D12);
const surface = Color(0xFF151922);

void main() => runApp(const RadyoAlarmApp());

class RadioStation {
  final String name;
  final String genre;
  final String url;
  final String country;
  const RadioStation(this.name, this.genre, this.url, {this.country = 'Türkiye'});
}

const stations = <RadioStation>[
  RadioStation('Power FM', 'Yabancı pop ve hit müzik', 'https://listen.powerapp.com.tr/powerfm/mpeg/icecast.audio'),
  RadioStation('Power Türk FM', 'Türkçe pop', 'https://live.powerapp.com.tr/powerturk/abr/powerturk/128/playlist.m3u8'),
  RadioStation('TRT FM', 'Türkçe müzik ve eğlence', 'https://radio-trtfm.live.trt.com.tr/master.m3u8'),
  RadioStation('Radyo 1', 'Haber, kültür ve programlar', 'https://radio-trtradyo1.live.trt.com.tr/master.m3u8'),
  RadioStation('TRT Türkü', 'Türk halk müziği', 'https://radio-trtturku.live.trt.com.tr/master.m3u8'),
  RadioStation('TRT Radyo Haber', 'Haber ve gündem', 'https://radio-trtradyohaber.live.trt.com.tr/master.m3u8'),
  RadioStation('Radyo İlef', 'Üniversite radyosu', 'https://radyoilef.ankara.edu.tr/live'),
];

class RadyoAlarmApp extends StatelessWidget {
  const RadyoAlarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Radyo Alarm',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(primary: accent, secondary: accent, surface: surface),
        appBarTheme: const AppBarTheme(backgroundColor: background, foregroundColor: Colors.white, surfaceTintColor: Colors.transparent),
        cardTheme: CardThemeData(color: surface, elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
        filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: const Color(0xFF17130A), textStyle: const TextStyle(fontWeight: FontWeight.w700), padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)))),
      ),
      home: const AnaSayfa(),
    );
  }
}

class AnaSayfa extends StatefulWidget {
  const AnaSayfa({super.key});
  @override
  State<AnaSayfa> createState() => _AnaSayfaState();
}

class _AnaSayfaState extends State<AnaSayfa> {
  final AudioPlayer player = AudioPlayer();
  final FlutterTts tts = FlutterTts();
  final TextEditingController urlController = TextEditingController();

  TimeOfDay alarmSaati = const TimeOfDay(hour: 7, minute: 0);
  bool alarmAcik = false;
  bool yukleniyor = false;
  bool bultenOkunuyor = false;
  bool radyoCalisiyor = false;
  String alarmMode = 'host'; // host, radio, host_radio
  String radyoAdi = 'Power FM';
  String radyoAdresi = stations.first.url;
  String konumAdi = 'İstanbul (varsayılan)';
  double enlem = 41.0082;
  double boylam = 28.9784;
  bool konumYukleniyor = false;
  String? hata;

  @override
  void initState() {
    super.initState();
    ayarlariYukle();
    _ttsAyarla();
    player.playerStateStream.listen((state) {
      if (mounted) setState(() => radyoCalisiyor = state.playing);
    });
  }

  Future<void> _ttsAyarla() async {
    await tts.setLanguage('tr-TR');
    await tts.setSpeechRate(0.42);
    await tts.setPitch(1.04);
    await tts.awaitSpeakCompletion(true);
    tts.setCompletionHandler(() { if (mounted) setState(() => bultenOkunuyor = false); });
    tts.setCancelHandler(() { if (mounted) setState(() => bultenOkunuyor = false); });
  }

  Future<void> ayarlariYukle() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      alarmSaati = TimeOfDay(hour: prefs.getInt('alarmSaat') ?? 7, minute: prefs.getInt('alarmDakika') ?? 0);
      alarmAcik = prefs.getBool('alarmAcik') ?? false;
      radyoAdi = prefs.getString('radyoAdi') ?? 'Power FM';
      radyoAdresi = prefs.getString('radyoAdresi') ?? stations.first.url;
      alarmMode = prefs.getString('alarmMode') ?? 'host';
      enlem = prefs.getDouble('havaEnlem') ?? 41.0082;
      boylam = prefs.getDouble('havaBoylam') ?? 28.9784;
      konumAdi = prefs.getString('havaKonumAdi') ?? 'İstanbul (varsayılan)';
    });
  }

  Future<void> konumuGuncelle() async {
    if (konumYukleniyor) return;
    setState(() { konumYukleniyor = true; hata = null; });
    try {
      final result = await alarmChannel.invokeMethod<Map<dynamic, dynamic>>('updateLocation').timeout(const Duration(seconds: 25));
      if (result == null) throw Exception('Konum bilgisi alınamadı.');
      final lat = (result['latitude'] as num).toDouble();
      final lon = (result['longitude'] as num).toDouble();
      final city = (result['city'] as String?)?.trim();
      final name = (city == null || city.isEmpty) ? 'Bulunduğun bölge' : city;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('havaEnlem', lat);
      await prefs.setDouble('havaBoylam', lon);
      await prefs.setString('havaKonumAdi', name);
      if (!mounted) return;
      setState(() { enlem = lat; boylam = lon; konumAdi = name; });
      mesaj('Hava durumu konumu $name olarak güncellendi.');
      if (alarmAcik) await alarmiKur();
    } catch (e) {
      if (mounted) {
        final message = e.toString().replaceFirst('PlatformException(', '').split(',').first;
        setState(() => hata = 'Konum alınamadı. Konum iznini ve telefonun konum servisini kontrol et. ($message)');
      }
    } finally {
      if (mounted) setState(() => konumYukleniyor = false);
    }
  }

  Future<void> ayarlariKaydet() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('alarmSaat', alarmSaati.hour);
    await prefs.setInt('alarmDakika', alarmSaati.minute);
    await prefs.setBool('alarmAcik', alarmAcik);
    await prefs.setString('radyoAdi', radyoAdi);
    await prefs.setString('radyoAdresi', radyoAdresi);
    await prefs.setString('alarmMode', alarmMode);
  }

  String get saatMetni => '${alarmSaati.hour.toString().padLeft(2, '0')}:${alarmSaati.minute.toString().padLeft(2, '0')}';
  bool get radyoModu => alarmMode == 'radio' || alarmMode == 'host_radio';
  String get seciliRadyoTuru {
    for (final station in stations) { if (station.name == radyoAdi) return station.genre; }
    return 'Özel internet yayını';
  }

  void mesaj(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating, backgroundColor: const Color(0xFF282E39)));
  }

  Future<void> saatiSec() async {
    final secim = await showTimePicker(
      context: context,
      initialTime: alarmSaati,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (secim == null || !mounted) return;
    setState(() => alarmSaati = secim);
    await ayarlariKaydet();
    if (alarmAcik) await alarmiKur();
  }

  Future<void> alarmiKur() async {
    try {
      await alarmChannel.invokeMethod('scheduleAlarm', {
        'hour': alarmSaati.hour,
        'minute': alarmSaati.minute,
        'url': radyoAdresi,
        'station': radyoAdi,
        'mode': alarmMode,
      });
      if (mounted) mesaj('Alarm her gün $saatMetni için kuruldu.');
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => alarmAcik = false);
      await ayarlariKaydet();
      mesaj(e.message ?? 'Alarm kurulamadı. Android kesin alarm iznini kontrol et.');
    } catch (e) {
      if (!mounted) return;
      setState(() => alarmAcik = false);
      await ayarlariKaydet();
      mesaj('Alarm kurulamadı: $e');
    }
  }

  Future<void> alarmiIptalEt() async {
    try {
      await alarmChannel.invokeMethod('cancelAlarm');
      if (mounted) mesaj('Alarm kapatıldı.');
    } catch (e) { if (mounted) mesaj('Alarm iptal edilirken hata oluştu: $e'); }
  }

  Future<void> moduSec(String mode) async {
    setState(() => alarmMode = mode);
    await ayarlariKaydet();
    if (alarmAcik) await alarmiKur();
  }

  Future<List<RadioStation>> _internetRadyolariAra(
    String query, {String countryCode = 'TR', String genreTag = ''}
  ) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final params = <String, String>{
        'hidebroken': 'true', 'limit': '100', 'order': 'clickcount', 'reverse': 'true',
      };
      if (countryCode.isNotEmpty) params['countrycode'] = countryCode;
      if (query.trim().isNotEmpty) params['name'] = query.trim();
      if (genreTag.isNotEmpty) params['tag'] = genreTag;
      final uri = Uri.https('de1.api.radio-browser.info', '/json/stations/search', params);
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 9));
      request.headers.set(HttpHeaders.userAgentHeader, 'RadyoAlarm/1.0');
      final response = await request.close().timeout(const Duration(seconds: 9));
      if (response.statusCode != 200) throw Exception('Radyo listesi alınamadı');
      final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
      final data = jsonDecode(body) as List<dynamic>;
      final found = <RadioStation>[];
      final seen = <String>{};
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final name = (item['name'] ?? '').toString().trim();
        final url = (item['url_resolved'] ?? item['url'] ?? '').toString().trim();
        final lastOk = item['lastcheckok'];
        if (name.isEmpty || url.isEmpty || (!url.startsWith('http://') && !url.startsWith('https://'))) continue;
        if (lastOk != null && lastOk != 1) continue;
        final key = '${name.toLowerCase()}|$url';
        if (!seen.add(key)) continue;
        final rawTags = (item['tags'] ?? '').toString().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).take(3).toList();
        final country = (item['country'] ?? '').toString().trim();
        found.add(RadioStation(name, rawTags.isEmpty ? 'Genel' : rawTags.join(' · '), url, country: country.isEmpty ? 'Diğer' : country));
      }
      return found;
    } finally {
      client?.close(force: true);
    }
  }

  Future<void> istasyonSec() async {
    final searchController = TextEditingController();
    List<RadioStation> results = List<RadioStation>.from(stations);
    bool searching = false;
    String? searchError;
    int searchVersion = 0;
    bool initialSearchStarted = false;
    String selectedCountry = 'TR';
    String selectedGenre = '';

    const countries = <String, String>{
      'TR': 'Türkiye', '': 'Tüm ülkeler', 'US': 'ABD', 'GB': 'Birleşik Krallık',
      'DE': 'Almanya', 'FR': 'Fransa', 'IT': 'İtalya', 'ES': 'İspanya',
      'NL': 'Hollanda', 'RU': 'Rusya', 'JP': 'Japonya', 'KR': 'Güney Kore',
      'BR': 'Brezilya', 'IN': 'Hindistan', 'CA': 'Kanada', 'AU': 'Avustralya',
    };
    const genres = <String, String>{
      '': 'Tüm türler', 'pop': 'Pop', 'rock': 'Rock', 'dance': 'Dans / EDM',
      'electronic': 'Elektronik', 'jazz': 'Caz', 'classical': 'Klasik',
      'news': 'Haber', 'talk': 'Sohbet / Talk', 'sports': 'Spor',
      'hip hop': 'Hip-hop', 'oldies': 'Nostalji', 'folk': 'Halk müziği',
      'country': 'Country', 'metal': 'Metal', 'reggae': 'Reggae',
      'religious': 'Dini yayınlar', 'turkish': 'Türkçe müzik',
    };

    Future<void> search(String query, StateSetter update) async {
      final version = ++searchVersion;
      update(() { searching = true; searchError = null; });
      try {
        final online = await _internetRadyolariAra(query, countryCode: selectedCountry, genreTag: selectedGenre);
        if (version != searchVersion) return;
        final merged = <RadioStation>[];
        final keys = <String>{};
        for (final station in [...online, ...stations]) {
          // Sabit Türkiye istasyonlarını yalnızca Türkiye filtresinde ekle.
          if (stations.contains(station) && selectedCountry.isNotEmpty && selectedCountry != 'TR') continue;
          if (selectedGenre.isNotEmpty && !station.genre.toLowerCase().contains(selectedGenre.toLowerCase())) continue;
          final key = '${station.name.toLowerCase()}|${station.url}';
          if (keys.add(key)) merged.add(station);
        }
        merged.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        update(() { results = merged; searching = false; });
      } catch (_) {
        if (version != searchVersion) return;
        final local = searchController.text.trim().toLowerCase();
        update(() {
          results = stations.where((s) => (local.isEmpty || s.name.toLowerCase().contains(local) || s.genre.toLowerCase().contains(local)) && (selectedGenre.isEmpty || s.genre.toLowerCase().contains(selectedGenre.toLowerCase()))).toList();
          searching = false;
          searchError = 'Kataloğa ulaşılamadı; çevrimdışı kayıtlı radyolar gösteriliyor.';
        });
      }
    }

    final secim = await showModalBottomSheet<RadioStation>(
      context: context, backgroundColor: surface, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (context) => StatefulBuilder(builder: (context, update) {
        if (!initialSearchStarted) {
          initialSearchStarted = true;
          Future.microtask(() => search('', update));
        }
        return SafeArea(child: SizedBox(
          height: MediaQuery.of(context).size.height * .9,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 14), child: Row(children: [
              Container(width: 44, height: 44, decoration: BoxDecoration(color: accent.withOpacity(.13), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.radio_rounded, color: accent, size: 26)),
              const SizedBox(width: 12), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Radyo keşfet', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                SizedBox(height: 3), Text('Ülke ve müzik türüne göre filtrele', style: TextStyle(fontSize: 12, color: Colors.white54)),
              ])),
            ])),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(
              controller: searchController, textInputAction: TextInputAction.search,
              onSubmitted: (value) => search(value, update),
              decoration: InputDecoration(hintText: 'Radyo adı ara: Kiss FM, Power FM…', prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: () => search(searchController.text, update)),
                filled: true, fillColor: const Color(0xFF222733), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(vertical: 14)),
            )),
            const Padding(padding: EdgeInsets.fromLTRB(18, 16, 18, 7), child: Text('ÜLKE', style: TextStyle(fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w800, color: Colors.white54))),
            SizedBox(height: 42, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: countries.entries.map((entry) {
              final active = selectedCountry == entry.key;
              return Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(entry.value), selected: active,
                onSelected: (_) { update(() => selectedCountry = entry.key); search(searchController.text, update); },
                selectedColor: accent, backgroundColor: const Color(0xFF222733), labelStyle: TextStyle(color: active ? const Color(0xFF17130A) : Colors.white70, fontWeight: FontWeight.w600), side: BorderSide.none, showCheckmark: false));
            }).toList())),
            const Padding(padding: EdgeInsets.fromLTRB(18, 14, 18, 7), child: Text('MÜZİK TÜRÜ', style: TextStyle(fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w800, color: Colors.white54))),
            SizedBox(height: 42, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: genres.entries.map((entry) {
              final active = selectedGenre == entry.key;
              return Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(entry.value), selected: active,
                onSelected: (_) { update(() => selectedGenre = entry.key); search(searchController.text, update); },
                selectedColor: accent, backgroundColor: const Color(0xFF222733), labelStyle: TextStyle(color: active ? const Color(0xFF17130A) : Colors.white70, fontWeight: FontWeight.w600), side: BorderSide.none, showCheckmark: false));
            }).toList())),
            Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 8), child: Row(children: [
              Expanded(child: Text(searchError ?? (searching ? 'İstasyonlar getiriliyor…' : '${results.length} istasyon · ${countries[selectedCountry]} · ${genres[selectedGenre]}'), style: TextStyle(color: searchError == null ? Colors.white54 : Colors.orangeAccent, fontSize: 11))),
              TextButton(onPressed: () { searchController.clear(); update(() { selectedCountry = 'TR'; selectedGenre = ''; }); search('', update); }, child: const Text('Sıfırla')),
            ])),
            const Divider(color: Colors.white12, height: 1),
            if (searching) const LinearProgressIndicator(minHeight: 2, color: accent, backgroundColor: Colors.white10),
            Expanded(child: results.isEmpty && !searching ? const Center(child: Text('Bu filtrelerde radyo bulunamadı.', style: TextStyle(color: Colors.white54))) : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12), itemCount: results.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                if (index == results.length) return Card(color: const Color(0xFF202631), child: ListTile(
                  leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: accent.withOpacity(.12), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.link_rounded, color: accent)),
                  title: const Text('Kendi radyonu ekle', style: TextStyle(fontWeight: FontWeight.w700)), subtitle: const Text('Yayın adresi / stream URL'), trailing: const Icon(Icons.chevron_right),
                  onTap: () async { Navigator.pop(context); await ozelRadyoEkle(); }));
                final station = results[index];
                final selected = radyoAdi == station.name && radyoAdresi == station.url;
                return Card(color: selected ? const Color(0xFF302B1E) : const Color(0xFF1C222D), child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: accent.withOpacity(.12), borderRadius: BorderRadius.circular(13)), child: Icon(station.name.toLowerCase().contains('trt') ? Icons.graphic_eq_rounded : Icons.radio_rounded, color: accent)),
                  title: Text(station.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text('${station.country}  •  ${station.genre.isEmpty ? 'Genel' : station.genre}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white54))),
                  trailing: Icon(selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded, color: selected ? accent : Colors.white38), onTap: () => Navigator.pop(context, station)));
              },
            )),
          ]),
        ));
      }),
    );
    searchController.dispose();
    if (secim == null || !mounted) return;
    try { await player.stop().timeout(const Duration(seconds: 3)); } catch (_) {}
    if (!mounted) return;
    setState(() { radyoAdi = secim.name; radyoAdresi = secim.url; hata = null; yukleniyor = false; });
    await ayarlariKaydet();
    if (alarmAcik) await alarmiKur();
    mesaj('${secim.name} seçildi.');
  }

  Future<void> ozelRadyoEkle() async {
    urlController.text = radyoAdresi;
    final sonuc = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      backgroundColor: surface,
      title: const Text('Özel radyo adresi'),
      content: TextField(controller: urlController, keyboardType: TextInputType.url, autofocus: true, decoration: const InputDecoration(labelText: 'Yayın URL adresi', hintText: 'https://...', border: OutlineInputBorder())),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')), FilledButton(onPressed: () => Navigator.pop(context, urlController.text.trim()), child: const Text('Kaydet'))],
    ));
    if (sonuc == null || !mounted) return;
    if (!sonuc.startsWith('http://') && !sonuc.startsWith('https://')) { mesaj('Geçerli bir HTTP veya HTTPS adresi gir.'); return; }
    try { await player.stop().timeout(const Duration(seconds: 3)); } catch (_) {}
    if (!mounted) return;
    setState(() { radyoAdi = 'Özel radyo'; radyoAdresi = sonuc; hata = null; yukleniyor = false; });
    await ayarlariKaydet();
    if (alarmAcik) await alarmiKur();
    mesaj('Radyo adresi kaydedildi.');
  }

  Future<String> sabahBulteniHazirla() async {
    final now = DateTime.now();
    const gunler = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
    const aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
    final tarih = '${now.day} ${aylar[now.month - 1]} ${gunler[now.weekday - 1]}';
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 7);
      final uri = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=$enlem&longitude=$boylam&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max,sunrise&timezone=auto&forecast_days=1');
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 8));
      final response = await request.close().timeout(const Duration(seconds: 8));
      final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) throw Exception('Hava durumu alınamadı');
      final json = jsonDecode(body) as Map<String, dynamic>;
      final current = json['current'] as Map<String, dynamic>;
      final daily = json['daily'] as Map<String, dynamic>;
      final temp = (current['temperature_2m'] as num).round();
      final code = (current['weather_code'] as num).toInt();
      final wind = (current['wind_speed_10m'] as num?)?.round();
      final max = (daily['temperature_2m_max'][0] as num).round();
      final min = (daily['temperature_2m_min'][0] as num).round();
      final rain = daily['precipitation_probability_max']?[0];
      final maxWind = daily['wind_speed_10m_max']?[0];
      final rainValue = rain == null ? null : (rain as num).round();
      final rainSentence = (rainValue ?? 0) >= 40 ? ' Yağış ihtimali yüzde $rainValue.' : '';
      final windSentence = ((maxWind != null && (maxWind as num) >= 30) || (wind ?? 0) >= 25)
          ? ' Rüzgâr zaman zaman kuvvetlenebilir.' : '';
      return 'Günaydın! Bugün $tarih. $konumAdi için hava ${_havaDurumuMetni(code)}, sıcaklık şu anda $temp derece. Günün en yüksek sıcaklığı $max, en düşük sıcaklığı $min derece olacak.$rainSentence$windSentence Güzel bir gün dilerim.';
    } catch (_) {
      return 'Günaydın! Bugün $tarih. Şu anda hava durumunu alamadım. Güncel tahmini kontrol etmeyi unutma. Güzel bir gün dilerim.';
    } finally { client?.close(force: true); }
  }

  String _havaDurumuMetni(int code) {
    if (code == 0) return 'açık';
    if (code == 1) return 'çoğunlukla açık';
    if (code == 2) return 'parçalı bulutlu';
    if (code == 3) return 'kapalı';
    if (code == 45 || code == 48) return 'sisli';
    if (code >= 51 && code <= 57) return 'çiseli';
    if (code >= 61 && code <= 67) return 'yağmurlu';
    if (code >= 71 && code <= 77) return 'kar yağışlı';
    if (code >= 80 && code <= 82) return 'sağanak yağışlı';
    if (code >= 85 && code <= 86) return 'kar sağanaklı';
    if (code >= 95) return 'gök gürültülü fırtınalı';
    return 'değişken';
  }

  Future<void> radyoyuCal() async {
    if (yukleniyor) return;
    setState(() { yukleniyor = true; hata = null; });
    try {
      await tts.stop();
      // Önceki bağlantıyı bırak. setUrl sonsuza kadar beklerse 12 sn sonra iptal et.
      try { await player.stop().timeout(const Duration(seconds: 3)); } catch (_) {}
      await player.setUrl(radyoAdresi).timeout(const Duration(seconds: 12));
      // play() yayının sonuna kadar tamamlanmadığından await ETME; aksi halde
      // arayüz sürekli "Bağlanıyor" durumunda kalır.
      player.play().catchError((Object _) {
        if (mounted) setState(() => hata = 'Radyo yayını kesildi. Başka bir istasyon deneyebilirsin.');
      });
    } catch (_) {
      try { await player.stop().timeout(const Duration(seconds: 2)); } catch (_) {}
      if (mounted) setState(() => hata = 'Radyo bağlanamadı veya yayın yanıt vermedi. Başka bir istasyon seçip tekrar dene.');
    } finally {
      if (mounted) setState(() => yukleniyor = false);
    }
  }

  Future<void> radyoyuDurdur() async {
    try { await player.stop().timeout(const Duration(seconds: 3)); } catch (_) {}
    if (mounted) setState(() { yukleniyor = false; radyoCalisiyor = false; });
  }

  Future<void> bulteniOku() async {
    if (bultenOkunuyor) { await tts.stop(); if (mounted) setState(() => bultenOkunuyor = false); return; }
    await player.pause();
    setState(() { bultenOkunuyor = true; hata = null; });
    try { await _ttsAyarla(); final text = await sabahBulteniHazirla(); await tts.speak(text); }
    catch (_) { if (mounted) setState(() { bultenOkunuyor = false; hata = 'Sesli okuma başlatılamadı.'; }); }
  }

  @override
  void dispose() { player.dispose(); tts.stop(); urlController.dispose(); super.dispose(); }

  Widget _modeCard({required String value, required IconData icon, required String title, required String description}) {
    final selected = alarmMode == value;
    return InkWell(
      onTap: () => moduSec(value), borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180), padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: selected ? const Color(0xFF2B281D) : const Color(0xFF151922), borderRadius: BorderRadius.circular(18), border: Border.all(color: selected ? accent : Colors.white10, width: selected ? 1.5 : 1)),
        child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: selected ? accent.withValues(alpha: .15) : const Color(0xFF252B36), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: selected ? accent : Colors.white70)),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)), const SizedBox(height: 4), Text(description, style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.35))])),
          const SizedBox(width: 8), Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? accent : Colors.white38),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final modeDescription = switch (alarmMode) {
      'radio' => 'Alarmda $radyoAdi çalacak.',
      'host_radio' => 'Önce günaydın ve hava durumu, ardından $radyoAdi.',
      _ => 'Alarmda konumuna göre günaydın bülteni ve canlı hava durumu okunacak.',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [Icon(Icons.wb_twilight, color: accent, size: 27), SizedBox(width: 10), Text('GÜNE BAŞLA', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 17))]),
        actions: [Padding(padding: const EdgeInsets.only(right: 16), child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: alarmAcik ? const Color(0xFF24392C) : const Color(0xFF252B36), borderRadius: BorderRadius.circular(20)), child: Row(children: [Container(width: 7, height: 7, decoration: BoxDecoration(color: alarmAcik ? const Color(0xFF66D98A) : Colors.white38, shape: BoxShape.circle)), const SizedBox(width: 6), Text(alarmAcik ? 'AKTİF' : 'KAPALI', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: .6))]))))],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 30), children: [
        const Text('Güne iyi başla.', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.8)),
        const SizedBox(height: 5),
        const Text('Alarmını ayarla, sabahını nasıl karşılayacağını seç.', style: TextStyle(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white10)),
          child: Row(children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.location_on_outlined, color: accent)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('HAVA DURUMU KONUMU', style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
              const SizedBox(height: 4),
              Text(konumAdi, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              const Text('Bülten bu konumun hava durumunu okur.', style: TextStyle(color: Colors.white54, fontSize: 11)),
            ])),
            const SizedBox(width: 8),
            TextButton(onPressed: konumYukleniyor ? null : konumuGuncelle, child: Text(konumYukleniyor ? 'ALINIYOR…' : 'KONUMUM')),
          ]),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF302A1C), Color(0xFF191B20), Color(0xFF151922)]), borderRadius: BorderRadius.circular(25), border: Border.all(color: accent.withValues(alpha: .25))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [Icon(Icons.alarm_rounded, color: accent, size: 18), SizedBox(width: 8), Text('GÜNLÜK ALARM', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.7))]),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(child: GestureDetector(onTap: saatiSec, child: Text(saatMetni, style: const TextStyle(fontSize: 64, height: 1.05, fontWeight: FontWeight.w300, letterSpacing: -3)))), IconButton.filledTonal(onPressed: saatiSec, tooltip: 'Alarm saatini değiştir', icon: const Icon(Icons.edit_calendar_outlined), style: IconButton.styleFrom(backgroundColor: Colors.white10, foregroundColor: Colors.white))]),
            const SizedBox(height: 15),
            Container(height: 1, color: Colors.white12),
            const SizedBox(height: 10),
            Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(alarmAcik ? 'Alarm etkin' : 'Alarm devre dışı', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)), const SizedBox(height: 3), Text(modeDescription, style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.35))])), Switch(value: alarmAcik, activeTrackColor: accent, onChanged: (value) async { setState(() => alarmAcik = value); await ayarlariKaydet(); if (value) { await alarmiKur(); } else { await alarmiIptalEt(); } })]),
          ]),
        ),
        const SizedBox(height: 25),
        const Text('ALARMDA NE ÇALSIN?', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
        const SizedBox(height: 10),
        _modeCard(value: 'host', icon: Icons.record_voice_over_rounded, title: 'Günaydın sunucusu', description: 'Konumuna göre sabah bülteni ve canlı hava durumu.'),
        const SizedBox(height: 9),
        _modeCard(value: 'radio', icon: Icons.radio_rounded, title: 'Radyo yayını', description: 'Seçtiğin istasyon doğrudan çalmaya başlar.'),
        const SizedBox(height: 9),
        _modeCard(value: 'host_radio', icon: Icons.queue_music_rounded, title: 'Sunucu + radyo', description: 'Önce sabah bülteni okunur, ardından radyo açılır.'),
        if (radyoModu) ...[
          const SizedBox(height: 22),
          const Text('SEÇİLİ RADYO', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          const SizedBox(height: 10),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFF282E39), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.radio, color: accent, size: 27)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(radyoAdi, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 4), Text(seciliRadyoTuru, style: const TextStyle(color: Colors.white60, fontSize: 12))])), TextButton(onPressed: istasyonSec, child: const Text('DEĞİŞTİR'))]))),
        ],
        const SizedBox(height: 23),
        const Text('ŞİMDİ DENE', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
        const SizedBox(height: 10),
        Row(children: [Expanded(child: OutlinedButton.icon(onPressed: bulteniOku, icon: Icon(bultenOkunuyor ? Icons.stop_rounded : Icons.volume_up_rounded), label: Text(bultenOkunuyor ? 'Konuşmayı durdur' : 'Bülteni dinle'), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))))), const SizedBox(width: 10), Expanded(child: OutlinedButton.icon(onPressed: yukleniyor ? null : (radyoCalisiyor ? radyoyuDurdur : radyoyuCal), icon: Icon(radyoCalisiyor ? Icons.stop_rounded : Icons.play_arrow_rounded), label: Text(yukleniyor ? 'Bağlanıyor' : radyoCalisiyor ? 'Radyoyu durdur' : 'Radyoyu dene'), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), foregroundColor: accent, side: BorderSide(color: accent.withValues(alpha: .45)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)))))]),
        if (hata != null) ...[const SizedBox(height: 12), Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF351B1B), borderRadius: BorderRadius.circular(14)), child: Text(hata!))],
        const SizedBox(height: 16),
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF131720), borderRadius: BorderRadius.circular(15)), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.info_outline, color: Colors.white54, size: 19), SizedBox(width: 10), Expanded(child: Text('Daha doğal bir ses için Android’de Metin okuma çıkışı ayarlarından Türkçe için yüksek kaliteli ses paketini indir. Mevcut ses, telefonda yüklü TTS motoruna bağlıdır.', style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.45)))])),
      ]),
    );
  }
}
