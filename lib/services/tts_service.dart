import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:easyconnect/features/settings/models/app_settings_model.dart';

class TeluguPhrases {
  static const Map<String, String> _phrases = {
    // Call states
    'కాల్ కనెక్ట్ చేయబడింది': 'లైన్ కలిసింది',
    'కాల్ కనెక్ట్ అయింది': 'లైన్ కలిసింది',
    'Call connected': 'లైన్ కలిసింది',
    
    'కాల్ ముగిసింది': 'కాల్ పెట్టేశారు',
    'Call ended': 'కాల్ పెట్టేశారు',
    
    'కనెక్ట్ అవుతోంది': 'కాల్ కలుపుతున్నా, ఉండు',
    'Call connecting': 'కాల్ కలుపుతున్నా, ఉండు',
    
    // Network
    'నెట్వర్క్ అందుబాటులో లేదు': 'సిగ్నల్ లేదు, చూసుకో',
    'No internet connection': 'సిగ్నల్ లేదు, చూసుకో',
    'No internet — WhatsApp features unavailable': 'సిగ్నల్ లేదు, చూసుకో',
    
    // Recipient Busy
    'లైన్ బిజీగా ఉంది': 'ఇప్పుడు మాట్లాడుతున్నారు, తర్వాత చేయి',
    'Line is busy': 'ఇప్పుడు మాట్లాడుతున్నారు, తర్వాత చేయి',
    'Recipient busy': 'ఇప్పుడు మాట్లాడుతున్నారు, తర్వాత చేయి',
    
    // Call not answered
    'కాల్ స్వీకరించలేదు': 'ఎత్తలేదు, మళ్ళీ చేయి',
    'Call not answered': 'ఎత్తలేదు, మళ్ళీ చేయి',
    
    // SOS
    'అత్యవసర సేవ యాక్టివేట్ అయింది': 'సాయం పంపిస్తున్నా, భయపడకు',
    'SOS activated': 'సాయం పంపిస్తున్నా, భయపడకు',
    
    // Permission
    'అనుమతి నిరాకరించబడింది': 'ఫోన్ వాడుకోవడానికి పర్మిషన్ ఇవ్వు',
    'Permission required': 'ఫోన్ వాడుకోవడానికి పర్మిషన్ ఇవ్వు',
    'Permission denied': 'ఫోన్ వాడుకోవడానికి పర్మిషన్ ఇవ్వు',
    
    // Battery Warnings
    'బ్యాటరీ తక్కువగా ఉంది': 'బ్యాటరీ అయిపోతోంది, చార్జ్ పెట్టు',
    'Low battery warning': 'బ్యాటరీ అయిపోతోంది, చార్జ్ పెట్టు',
    'battery_20': 'బ్యాటరీ తక్కువైపోతోంది, చార్జ్ పెట్టు',
    'battery_10': 'అయ్యో, బ్యాటరీ పోతోంది! వెంటనే చార్జ్ పెట్టు',
    'battery_5': 'బ్యాటరీ దాదాపు అయిపోయింది, ఇప్పుడే చార్జ్ పెట్టు!',
    'battery_charging': 'చార్జ్ అవుతోంది, సరే',
    
    // Fallbacks
    'పేరు లేదు': 'పేరు లేదు',
    'No name': 'పేరు లేదు',

    // UI Navigation & Prompts
    'EasyConnect ready': 'ఈజీకనెక్ట్ రెడీగా ఉంది',
    'Voice guide turned off': 'వాయిస్ గైడ్ ఆఫ్ చేసాను',
    'Voice guide turned on': 'వాయిస్ గైడ్ ఆన్ చేసాను',
    'Showing Contacts Screen': 'ఫోన్ నెంబర్లు చూపిస్తున్నా',
    'Showing Keypad Dialer': 'నెంబర్లు నొక్కే బోర్డ్ చూపిస్తున్నా',
    'Showing Call History': 'మునుపటి కాల్స్ చూపిస్తున్నా',
    'Contact saved.': 'నెంబర్ సేవ్ అయింది',
    'Too many attempts. Please wait.': 'చాలా సార్లు తప్పుగా నొక్కావు, కాసేపు ఆగు',
    
    // WhatsApp & Voice Messages
    'WhatsApp is not installed. Cannot send message.': 'వాట్సాప్ ఇన్స్టాల్ అయ్యి లేదు',
    'WhatsApp is not installed.': 'వాట్సాప్ ఇన్స్టాల్ అయ్యి లేదు',
    'Sending message': 'మెసేజ్ పంపిస్తున్నా, ఉండు',
    'Message sent': 'మెసేజ్ వెళ్ళిపోయింది',
    
    // Other errors & fallbacks
    'Something went wrong. Please try again.': 'ఏదో సమస్య వచ్చింది, మళ్ళీ ట్రై చెయ్',
    
    // Dialer gestures
    'తొలగించబడింది': 'తీసేశాను',
    'deleted': 'తీసేశాను',
    'అన్నీ తొలగించబడ్డాయి': 'అన్నీ తీసేశాను',
    'cleared': 'అన్నీ తీసేశాను',
    
    // SIM warning alerts
    'NO SIM CARD FOUND (Check card tray)': 'సిమ్ కార్డు లేదు',
    'SIM CARD LOCKED (PIN/PUK needed)': 'సిమ్ కార్డు లాక్ అయింది',
    'SIM CARD ERROR (Broken or disabled)': 'సిమ్ కార్డు పని చేయడం లేదు',
    'SIM CARD DISCONNECTED': 'సిమ్ కార్డు డిస్-కనెక్ట్ అయింది',
    'Warning: No SIM card found. Please check your SIM card tray.': 'ఫోన్ లో సిమ్ కార్డు లేదు, మీ వాళ్ళని ఒకసారి సిమ్ కార్డు వేయమనండి',
    'Warning: SIM card is locked. PIN or PUK is required.': 'సిమ్ కార్డు లాక్ అయింది, మీ వాళ్ళని పిన్ నొక్కమనండి',
    'Warning: SIM card error. Your SIM card is broken or disabled.': 'సిమ్ కార్డు పని చేయట్లేదు, మీ వాళ్ళని ఒకసారి చూడమనండి',
    'Warning: SIM card disconnected.': 'సిమ్ కార్డు డిస్-కనెక్ట్ అయింది, మీ వాళ్ళని ఒకసారి చూడమనండి',
    
    // Incoming call announcements
    'incoming_call': 'కాల్ వస్తోంది',
    'incoming_unknown': 'ఎవరో కాల్ చేస్తున్నారు',
    'call_missed': 'కాల్ మిస్ అయింది',
    'call_cut': 'కాల్ కట్ అయింది',
    'no_sim': 'సిమ్ కార్డు లేదు, కాల్ చేయలేము',
    'flight_mode': 'ఫ్లైట్ మోడ్ ఆన్ ఉంది, కాల్ రాదు',
    
    // Missing countdowns & calling alerts
    '3': 'మూడు',
    '2': 'రెండు',
    '1': 'ఒకటి',
    'This contact has no phone number saved.': 'ఈ నెంబర్ సేవ్ చేసి లేదు',
  };

  static bool isStaticPhrase(String input) {
    final trimmed = input.trim();
    if (_phrases.containsKey(trimmed) || _phrases.containsValue(trimmed)) {
      return true;
    }
    if (trimmed.startsWith('Calling ') ||
        trimmed.startsWith('Placing call to ') ||
        trimmed.startsWith('Emergency message sent via WhatsApp to ') ||
        trimmed.startsWith('Emergency SMS sent to ') ||
        trimmed.startsWith('incoming_known:') ||
        trimmed.startsWith('second_incoming:')) {
      return false;
    }
    return false;
  }

  static String getSpokenPhrase(String input) {
    final trimmed = input.trim();
    if (_phrases.containsKey(trimmed)) {
      return _phrases[trimmed]!;
    }

    if (trimmed.startsWith('Calling ')) {
      final name = trimmed.substring('Calling '.length);
      return "$name కి కాల్ కలుపుతున్నా, ఉండు";
    }
    
    if (trimmed.endsWith(' కి కాల్ చేస్తున్నారు')) {
      final name = trimmed.substring(0, trimmed.length - ' కి కాల్ చేస్తున్నారు'.length);
      return "$name కి కాల్ కలుపుతున్నా, ఉండు";
    }

    if (trimmed.startsWith('Placing call to ')) {
      final name = trimmed.substring('Placing call to '.length);
      return "$name కి కాల్ కలుపుతున్నా, ఉండు";
    }

    if (trimmed.endsWith(' కి కాల్ ప్రారంభించబడింది')) {
      final name = trimmed.substring(0, trimmed.length - ' కి కాల్ ప్రారంభించబడింది'.length);
      return "$name కి కాల్ కలుపుతున్నా, ఉండు";
    }

    if (trimmed.endsWith(' నుండి ఇన్‌కమింగ్ కాల్ వస్తోంది')) {
      final name = trimmed.substring(0, trimmed.length - ' నుండి ఇన్‌కమింగ్ కాల్ వస్తోంది'.length);
      return "$name నుండి కాల్ వస్తోంది";
    }

    if (trimmed.endsWith(' తో వీడియో కాల్ ప్రారంభిస్తున్నారు')) {
      final name = trimmed.substring(0, trimmed.length - ' తో వీడియో కాల్ ప్రారంభిస్తున్నారు'.length);
      return "$name తో వీడియో కాల్, ఉండు";
    }

    if (trimmed.startsWith('No WhatsApp number saved for ')) {
      final name = trimmed.substring('No WhatsApp number saved for '.length);
      final cleanedName = name.endsWith('.') ? name.substring(0, name.length - 1) : name;
      return "$cleanedName కి వాట్సాప్ నెంబర్ సేవ్ చేసి లేదు";
    }

    if (trimmed.endsWith("was not saved in your phone's address book. I have automatically added her now. Please wait a moment for WhatsApp to sync, then try again.") || 
        trimmed.endsWith("was not saved in your phone's address book. I have automatically added them now. Please wait a moment for WhatsApp to sync, then try again.")) {
      final name = trimmed.split(' ')[0];
      return "$name పేరు మీ ఫోన్ లో సేవ్ చేసి లేదు. నేను ఇప్పుడు సేవ్ చేసాను. కాసేపు ఆగి మళ్ళీ ట్రై చెయ్యి.";
    }

    if (trimmed.startsWith('Warning. NO SIM CARD FOUND (Check card tray).')) {
      return "ఫోన్ లో సిమ్ కార్డు లేదు, మీ వాళ్ళని ఒకసారి సిమ్ కార్డు వేయమనండి";
    }
    if (trimmed.startsWith('Warning. SIM CARD LOCKED (PIN/PUK needed).')) {
      return "సిమ్ కార్డు లాక్ అయింది, మీ వాళ్ళని పిన్ నొక్కమనండి";
    }
    if (trimmed.startsWith('Warning. SIM CARD ERROR (Broken or disabled).')) {
      return "సిమ్ కార్డు పని చేయట్లేదు, మీ వాళ్ళని ఒకసారి చూడమనండి";
    }
    if (trimmed.startsWith('Warning. SIM CARD DISCONNECTED.')) {
      return "సిమ్ కార్డు డిస్-కనెక్ట్ అయింది, మీ వాళ్ళని ఒకసారి చూడమనండి";
    }
    
    if (trimmed.startsWith('Emergency message sent via WhatsApp to ')) {
      final name = trimmed.substring('Emergency message sent via WhatsApp to '.length);
      final cleanedName = name.endsWith('.') ? name.substring(0, name.length - 1) : name;
      return "$cleanedName కి వాట్సాప్ లో అత్యవసర మెసేజ్ పంపించాను";
    }
    if (trimmed.startsWith('Emergency SMS sent to ')) {
      final name = trimmed.substring('Emergency SMS sent to '.length);
      final cleanedName = name.endsWith('.') ? name.substring(0, name.length - 1) : name;
      return "$cleanedName కి అత్యవసర మెసేజ్ పంపించాను";
    }
    if (trimmed.startsWith('Emergency contact not set. Ask your family to set this up.')) {
      return "అత్యవసర నెంబర్ సెట్ చేయలేదు, మీ ఇంట్లో వాళ్ళని సెట్ చేయమనండి";
    }

    if (trimmed.startsWith('incoming_known:')) {
      final name = trimmed.substring('incoming_known:'.length);
      return "$name నుండి కాల్ వస్తోంది";
    }
    if (trimmed.startsWith('second_incoming:')) {
      final name = trimmed.substring('second_incoming:'.length);
      return "$name నుండి ఇంకో కాల్ వస్తోంది";
    }

    return trimmed;
  }
}

class HindiPhrases {
  static const Map<String, String> _phrases = {
    // Call states
    'Call connected': 'कॉल जुड़ गया है',
    'Call ended': 'कॉल समाप्त हो गया',
    'Call connecting': 'कॉल मिलाया जा रहा है, रुकिए',
    
    // Network
    'No internet connection': 'इंटरनेट नहीं चल रहा है, चेक करें',
    'No internet — WhatsApp features unavailable': 'इंटरनेट नहीं चल रहा है, चेक करें',
    
    // Recipient Busy
    'Line is busy': 'लाइन व्यस्त है, बाद में प्रयास करें',
    'Recipient busy': 'लाइन व्यस्त है, बाद में प्रयास करें',
    
    // Call not answered
    'Call not answered': 'कॉल नहीं उठाया गया, फिर से प्रयास करें',
    
    // SOS
    'SOS activated': 'मदद भेजी जा रही है, घबराएं नहीं',
    'అత్యవసర సమాచారం పంపించాము': 'आपातकालीन संदेश भेज दिए गए हैं',
    
    // Permission
    'Permission required': 'फ़ोन का उपयोग करने के लिए अनुमति दें',
    'Permission denied': 'फ़ोन का उपयोग करने के लिए अनुमति दें',
    
    // Battery Warnings
    'battery_20': 'बैटरी कम हो रही है, चार्ज पर लगाएं',
    'battery_10': 'बैटरी बहुत कम है, कृपया चार्ज पर लगाएं',
    'battery_5': 'बैटरी खत्म होने वाली है, अभी चार्ज पर लगाएं!',
    'battery_charging': 'चार्ज हो रहा है',
    
    // Fallbacks
    'No name': 'कोई नाम नहीं',
    'పేరు లేదు': 'कोई नाम नहीं',

    // UI Navigation & Prompts
    'EasyConnect ready': 'ईज़ीकनेक्ट तैयार है',
    'Voice guide turned off': 'आवाज बंद कर दी गई है',
    'Voice guide turned on': 'आवाज चालू कर दी गई है',
    'Showing Contacts Screen': 'संपर्क दिखाए जा रहे हैं',
    'Showing Keypad Dialer': 'नंबर डायल करने का बोर्ड दिखाया जा रहा है',
    'Showing Call History': 'पुराने कॉल दिखाए जा रहे हैं',
    'Contact saved.': 'संपर्क सहेज लिया गया है',
    'Too many attempts. Please wait.': 'बहुत सारे प्रयास किए गए, कृपया प्रतीक्षा करें',
    
    // WhatsApp & Voice Messages
    'WhatsApp is not installed. Cannot send message.': 'व्हाट्सएप इंस्टॉल नहीं है, मैसेज नहीं भेज सकते',
    'WhatsApp is not installed.': 'व्हाट्सएप इंस्टॉल नहीं है',
    'Sending message': 'संदेश भेजा जा रहा है, रुकिए',
    'Message sent': 'संदेश भेज दिया गया है',
    'Something went wrong. Please try again.': 'कुछ गड़बड़ हो गई, फिर से प्रयास करें',
    
    // SIM warnings
    'Warning: No SIM card found. Please check your SIM card tray.': 'सिम कार्ड नहीं मिला, कृपया सिम कार्ड चेक करें',
    'Warning: SIM card is locked. PIN or PUK is required.': 'सिम कार्ड लॉक है, पिन की आवश्यकता है',
    'Warning: SIM card error. Your SIM card is broken or disabled.': 'सिम कार्ड में कोई खराबी है, कृपया चेक करें',
    'Warning: SIM card disconnected.': 'सिम कार्ड डिस्कनेक्ट हो गया है',
    
    // Emergency countdown
    '3': 'तीन',
    '2': 'दो',
    '1': 'एक',
    
    // Call errors
    'This contact has no phone number saved.': 'इस संपर्क का कोई नंबर सहेजा नहीं गया है',
  };

  static bool isStaticPhrase(String input) {
    final trimmed = input.trim();
    if (_phrases.containsKey(trimmed) || _phrases.containsValue(trimmed)) {
      return true;
    }
    if (trimmed.startsWith('Calling ') ||
        trimmed.startsWith('Placing call to ') ||
        trimmed.startsWith('Emergency message sent via WhatsApp to ') ||
        trimmed.startsWith('Emergency SMS sent to ') ||
        trimmed.startsWith('incoming_known:') ||
        trimmed.startsWith('second_incoming:')) {
      return false;
    }
    return false;
  }

  static String getSpokenPhrase(String input) {
    final trimmed = input.trim();
    if (_phrases.containsKey(trimmed)) {
      return _phrases[trimmed]!;
    }

    if (trimmed.startsWith('Calling ')) {
      final name = trimmed.substring('Calling '.length);
      return "$name को कॉल किया जा रहा है, रुकिए";
    }

    if (trimmed.startsWith('Placing call to ')) {
      final name = trimmed.substring('Placing call to '.length);
      return "$name को कॉल किया जा रहा है, रुकिए";
    }

    if (trimmed.startsWith('incoming_known:')) {
      final name = trimmed.substring('incoming_known:'.length);
      return "$name से कॉल आ रही है";
    }

    if (trimmed.startsWith('second_incoming:')) {
      final name = trimmed.substring('second_incoming:'.length);
      return "$name से एक और कॉल आ रही है";
    }

    if (trimmed.startsWith('No WhatsApp number saved for ')) {
      final name = trimmed.substring('No WhatsApp number saved for '.length);
      final cleanedName = name.endsWith('.') ? name.substring(0, name.length - 1) : name;
      return "$cleanedName के लिए कोई व्हाट्सएप नंबर सहेजा नहीं गया है";
    }

    if (trimmed.endsWith("was not saved in your phone's address book. I have automatically added her now. Please wait a moment for WhatsApp to sync, then try again.") || 
        trimmed.endsWith("was not saved in your phone's address book. I have automatically added them now. Please wait a moment for WhatsApp to sync, then try again.")) {
      final name = trimmed.split(' ')[0];
      return "$name का नाम आपके फ़ोन में सहेजा नहीं गया था। मैंने इसे अभी सहेज लिया है। थोड़ी देर बाद फिर से प्रयास करें।";
    }

    if (trimmed.startsWith('Emergency message sent via WhatsApp to ')) {
      final name = trimmed.substring('Emergency message sent via WhatsApp to '.length);
      final cleanedName = name.endsWith('.') ? name.substring(0, name.length - 1) : name;
      return "$cleanedName को व्हाट्सएप पर आपातकालीन संदेश भेज दिया गया है";
    }
    if (trimmed.startsWith('Emergency SMS sent to ')) {
      final name = trimmed.substring('Emergency SMS sent to '.length);
      final cleanedName = name.endsWith('.') ? name.substring(0, name.length - 1) : name;
      return "$cleanedName को आपातकालीन संदेश भेज दिया गया है";
    }

    if (trimmed.endsWith(' కి మెసేజ్ పంపించాను') || trimmed.endsWith(' కి వాట్సాప్ లో అత్యవసర మెసేజ్ పంపించాను')) {
      final name = trimmed.split(' ')[0];
      return "$name को आपातकालीन संदेश भेज दिया गया है";
    }

    return trimmed;
  }
}

class TTSService {
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentLanguage;

  Future<void> init({String languageCode = 'en'}) async {
    if (_currentLanguage == languageCode) {
      return; // Already initialized for this language. Bypass expensive platform-bridge calls!
    }

    try {
      final locale = _getLocale(languageCode);
      await _flutterTts.setLanguage(locale);
      await _flutterTts.setSpeechRate(0.5); // Warm and fluid native speech rate
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0); // Warm and natural pitch for voice clarity
      
      if (languageCode == 'te') {
        final List<dynamic>? voices = await _flutterTts.getVoices;
        if (voices != null) {
          // Look for neural high-fidelity 'network' voice first, fall back to standard local te-IN
          final teVoice = voices.firstWhere(
            (v) {
              final name = v['name']?.toString().toLowerCase() ?? '';
              final loc = v['locale']?.toString().toLowerCase() ?? '';
              return (loc.contains('te-in') || loc.contains('te_in')) && name.contains('network');
            },
            orElse: () => voices.firstWhere(
              (v) {
                final loc = v['locale']?.toString().toLowerCase() ?? '';
                return loc.contains('te-in') || loc.contains('te_in');
              },
              orElse: () => null,
            ),
          );
          if (teVoice != null) {
            await _flutterTts.setVoice(Map<String, String>.from(teVoice as Map));
          }
        }
      }
      _currentLanguage = languageCode;
    } catch (e) {
      _currentLanguage = null;
      debugPrint('Error during TTSService.init for $languageCode: $e');
    }
  }

  Future<void> speak(String text, {String? forceLanguage, bool isDuringActiveCall = false, bool useSystemTts = true}) async {
    final settingsBox = Hive.isBoxOpen('settings') ? Hive.box<AppSettings>('settings') : null;
    String languageCode = forceLanguage ?? 'en';
    if (forceLanguage == null && settingsBox != null && settingsBox.isNotEmpty) {
      final settings = settingsBox.values.first;
      if (!settings.voiceEnabled) {
        return;
      }
      languageCode = settings.language;
    }

    // Stop any currently playing audio/TTS first to prevent overlapping sounds
    await stop();

    String textToSpeak = text;
    if (languageCode == 'te') {
      textToSpeak = TeluguPhrases.getSpokenPhrase(text);
    } else if (languageCode == 'hi') {
      textToSpeak = HindiPhrases.getSpokenPhrase(text);
    }

    // Dynamic names and custom texts can use high-fidelity online TTS when online
    // to provide warm, native pronunciation (Google Translate voice). Offline caching
    // ensures subsequent plays are instant and offline-capable.
    final useOfflineTts = useSystemTts;

    if ((languageCode == 'te' || languageCode == 'hi') && !useOfflineTts) {
      try {
        // Try playing premium Google Translate online TTS with offline caching
        final dir = await getApplicationDocumentsDirectory();
        final cacheFolder = Directory('${dir.path}/tts_cache');
        if (!await cacheFolder.exists()) {
          await cacheFolder.create(recursive: true);
        }

        final fileName = '${languageCode}_voice_${textToSpeak.hashCode}.mp3';
        final file = File('${cacheFolder.path}/$fileName');

        if (await file.exists()) {
          // Play cached offline native voice file
          await _audioPlayer.play(DeviceFileSource(file.path), volume: isDuringActiveCall ? 0.25 : 1.0);
          return;
        }

        // Check if device is connected to the internet
        final connectivityResult = await Connectivity().checkConnectivity();
        final hasInternet = !connectivityResult.contains(ConnectivityResult.none);

        if (hasInternet) {
          final url = 'https://translate.google.com/translate_tts?ie=UTF-8&tl=$languageCode&client=tw-ob&q=${Uri.encodeComponent(textToSpeak)}';
          final client = HttpClient();
          try {
            final request = await client.getUrl(Uri.parse(url));
            final response = await request.close();
            if (response.statusCode == 200) {
              final bytes = await response.fold<List<int>>([], (p, e) => p..addAll(e));
              await file.writeAsBytes(bytes);
              await _audioPlayer.play(DeviceFileSource(file.path), volume: isDuringActiveCall ? 0.25 : 1.0);
              return;
            }
          } catch (e) {
            debugPrint('Failed to download Translate TTS: $e');
          } finally {
            client.close();
          }
        }
      } catch (e) {
        debugPrint('Cache/Connectivity TTS play failed: $e');
      }
    }

    // Standard Fallback: System Offline TTS (e.g. for non-Telugu/Hindi, dynamic custom names, or offline first-time run)
    await init(languageCode: languageCode);
    if (isDuringActiveCall) {
      await _flutterTts.setVolume(0.25);
    }
    await _flutterTts.speak(textToSpeak);
    if (isDuringActiveCall) {
      // Restore volume shortly after synthesis queues
      Future.delayed(const Duration(seconds: 4), () async {
        await _flutterTts.setVolume(1.0);
      });
    }
  }

  Future<void> stop() async {
    try {
      await _flutterTts.stop();
      await _audioPlayer.stop();
    } catch (e) {
      debugPrint('Error stopping TTS/AudioPlayer: $e');
    }
  }

  Future<void> setLanguage(String langCode) async {
    await init(languageCode: langCode);
  }

  String _getLocale(String langCode) {
    switch (langCode) {
      case 'hi':
        return 'hi-IN';
      case 'te':
        return 'te-IN';
      case 'en':
      default:
        return 'en-IN';
    }
  }
}

final ttsServiceProvider = Provider<TTSService>((ref) => TTSService());
