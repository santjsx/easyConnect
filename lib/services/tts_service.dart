import 'dart:io';
import 'dart:async';
import 'dart:convert';
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
    'No name saved': 'పేరు లేదు',

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
    'Something went wrong. Please try again.': 'ఏదో సమస్య వచ్చింది, మళ్ళీ ట్రై చెయ్',
    'Backup failed. Please try again.': 'బ్యాకప్ విఫలమైంది. దయచేసి మళ్ళీ ప్రయత్నించండి.',
    'Restore failed. Please check the backup file.': 'పునరుద్ధరణ విఫలమైంది. దయచేసి బ్యాకప్ ఫైల్‌ను తనిఖీ చేయండి.',
    'Data restored successfully': 'డేటా విజయవంతంగా పునరుద్ధరించబడింది',
    
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
    
    // Countdowns & calling alerts
    '3': 'మూడు',
    '2': 'రెండు',
    '1': 'ఒకటి',
    'This contact has no phone number saved.': 'ఈ నెంబర్ సేవ్ చేసి లేదు',
    
    // Unification additions
    'Layout changed to Classic Mode': 'లేఅవుట్ క్లాసిక్ మోడ్‌కు మార్చబడింది',
    'Layout changed to Modern Mode': 'లేఅవుట్ మోడరన్ మోడ్‌కు మార్చబడింది',
    'Permission required to show incoming calls on screen.': 'ఫోన్ కాల్ వచ్చినప్పుడు స్క్రీన్ మీద చూపించడానికి పర్మిషన్ ఇవ్వు. ఆ పెద్ద బటన్ నొక్కు',
    'Rearranging mode active. Long press and drag cards to sort.': 'కార్డుల క్రమాన్ని మార్చే మోడ్ ఆన్ అయింది. మార్చడానికి కార్డును నొక్కి పట్టుకుని లాగండి.',
    'Rearranging mode inactive.': 'కార్డుల క్రమాన్ని మార్చే మోడ్ ఆఫ్ అయింది.',
    'Emergency contact not set. Ask your family to set this up.': 'అత్యవసర నెంబర్ సెట్ చేయలేదు, మీ ఇంట్లో వాళ్ళని సెట్ చేయమనండి',
    'Emergency messages sent': 'అత్యవసర సమాచారం పంపించాము',
    'No WhatsApp number saved. Making a standard phone call.': 'వాట్సాప్ నెంబర్ లేదు. మామూలు ఫోన్ కాల్ చేస్తున్నాను.',
    'microphone_muted': 'మైక్రోఫోన్ ఆఫ్ చేయబడింది',
    'microphone_unmuted': 'మైక్రోఫోన్ ఆన్ చేయబడింది',
    'speaker_loud': 'స్పీకర్ ఆన్ చేయబడింది',
    'speaker_soft': 'స్పీకర్ ఆఫ్ చేయబడింది',
    'incoming_guided_unknown': 'ఎవరో కాల్ చేస్తున్నారు. మాట్లాడటానికి ఆకుపచ్చ బటన్ నొక్కండి, వద్దనుకుంటే ఎరుపు బటన్ నొక్కండి.',
  };

  static bool isStaticPhrase(String input) {
    final trimmed = input.trim();
    if (_phrases.containsKey(trimmed) || _phrases.containsValue(trimmed)) {
      return true;
    }
    if (trimmed.startsWith('Calling ') ||
        trimmed.startsWith('Placing call to ') ||
        trimmed.startsWith('Starting video call with ') ||
        trimmed.startsWith('Sent message to ') ||
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

    if (trimmed.startsWith('Starting video call with ')) {
      final name = trimmed.substring('Starting video call with '.length);
      return "$name తో వీడియో కాల్, ఉండు";
    }

    if (trimmed.startsWith('To connect with ')) {
      final nameEndIndex = trimmed.indexOf(', tap the green button');
      if (nameEndIndex != -1) {
        final name = trimmed.substring('To connect with '.length, nameEndIndex);
        return "$name కి ఫోన్ చేయడానికి ఆకుపచ్చ బటన్, వీడియో కాల్ కి నీలం బటన్, లేదా వాయిస్ మెసేజ్ కి నారింజ బటన్ నొక్కండి.";
      }
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
    if (trimmed.startsWith('Sent message to ')) {
      final name = trimmed.substring('Sent message to '.length);
      return "$name కి మెసేజ్ పంపించాను";
    }
    if (trimmed.startsWith('incoming_guided_known:')) {
      final name = trimmed.substring('incoming_guided_known:'.length);
      return "$name నుండి ఫోన్ వస్తోంది. మాట్లాడటానికి ఆకుపచ్చ బటన్ నొక్కండి, వద్దనుకుంటే ఎరుపు బటన్ నొక్కండి.";
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
    'No name saved': 'कोई नाम नहीं',
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
    'Backup failed. Please try again.': 'बैकअप विफल रहा। कृपया पुनः प्रयास करें।',
    'Restore failed. Please check the backup file.': 'पुनर्प्राप्ति विफल रही। कृपया बैकअप फ़ाइल की जांच करें।',
    'Data restored successfully': 'डेटा सफलतापूर्वक पुनर्प्राप्त कर लिया गया है।',
    
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

    // Unification additions
    'deleted': 'हटाया गया',
    'cleared': 'साफ़ किया गया',
    'incoming_call': 'कॉल आ रही है',
    'incoming_unknown': 'अनजान नंबर से कॉल आ रही है',
    'call_missed': 'कॉल छूट गया',
    'call_cut': 'कॉल समाप्त हो गया',
    'no_sim': 'सिम कार्ड नहीं है, कॉल नहीं कर सकते',
    'flight_mode': 'फ्लाइट मोड चालू है, कॉल नहीं कर सकते',
    'Layout changed to Classic Mode': 'लेआउट क्लासिक मोड में बदल दिया गया है',
    'Layout changed to Modern Mode': 'लेआउट मॉडर्न मोड में बदल दिया गया है',
    'Permission required to show incoming calls on screen.': 'फ़ोन कॉल आने पर स्क्रीन पर दिखाने के लिए अनुमति दें। उस बड़े बटन को दबाएं।',
    'Rearranging mode active. Long press and drag cards to sort.': 'कार्ड व्यवस्थित करने का मोड चालू है। क्रम बदलने के लिए कार्ड को दबाकर रखें और खींचें।',
    'Rearranging mode inactive.': 'कार्ड व्यवस्थित करने का मोड बंद है।',
    'Emergency contact not set. Ask your family to set this up.': 'आपातकालीन संपर्क सेट नहीं है। अपने परिवार से इसे सेट करने के लिए कहें।',
    'Emergency messages sent': 'आपातकालीन संदेश भेज दिए गए हैं',
    'No WhatsApp number saved. Making a standard phone call.': 'व्हाट्सएप नंबर नहीं है। सामान्य फोन कॉल किया जा रहा है।',
    'microphone_muted': 'माइक बंद कर दिया गया है',
    'microphone_unmuted': 'माइक चालू कर दिया गया है',
    'speaker_loud': 'स्पीकर चालू कर दिया गया है',
    'speaker_soft': 'स्पीकर बंद कर दिया गया है',
    'incoming_guided_unknown': 'अनजान नंबर से कॉल आ रही है। बात करने के लिए हरा बटन दबाएं, बंद करने के लिए लाल बटन दबाएं।',
  };

  static bool isStaticPhrase(String input) {
    final trimmed = input.trim();
    if (_phrases.containsKey(trimmed) || _phrases.containsValue(trimmed)) {
      return true;
    }
    if (trimmed.startsWith('Calling ') ||
        trimmed.startsWith('Placing call to ') ||
        trimmed.startsWith('Starting video call with ') ||
        trimmed.startsWith('Sent message to ') ||
        trimmed.startsWith('Emergency message sent via WhatsApp to ') ||
        trimmed.startsWith('Emergency SMS sent to ') ||
        trimmed.startsWith('incoming_known:') ||
        trimmed.startsWith('second_incoming:') ||
        trimmed.startsWith('To connect with ')) {
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

    if (trimmed.startsWith('Starting video call with ')) {
      final name = trimmed.substring('Starting video call with '.length);
      return "$name के साथ वीडियो कॉल शुरू की जा रही है, रुकिए";
    }

    if (trimmed.startsWith('To connect with ')) {
      final nameEndIndex = trimmed.indexOf(', tap the green button');
      if (nameEndIndex != -1) {
        final name = trimmed.substring('To connect with '.length, nameEndIndex);
        return "$name को फ़ोन करने के लिए हरा बटन, वीडियो कॉल के लिए नीला बटन, या आवाज़ संदेश के लिए नारंगी बटन दबाएं।";
      }
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

    if (trimmed.startsWith('Sent message to ')) {
      final name = trimmed.substring('Sent message to '.length);
      return "$name को संदेश भेज दिया गया है";
    }

    if (trimmed.startsWith('Emergency contact not set. Ask your family to set this up.')) {
      return "आपातकालीन संपर्क सेट नहीं है। अपने परिवार से इसे सेट करने के लिए कहें।";
    }
    if (trimmed.startsWith('incoming_guided_known:')) {
      final name = trimmed.substring('incoming_guided_known:'.length);
      return "$name से कॉल आ रही है। बात करने के लिए हरा बटन दबाएं, बंद करने के लिए लाल बटन दबाएं।";
    }

    return trimmed;
  }
}

class EnglishPhrases {
  static const Map<String, String> _phrases = {
    // Call states
    'Call connected': 'Call connected',
    'Call ended': 'Call ended',
    'Call connecting': 'Connecting your call, please wait',
    
    // Network
    'No internet connection': 'No internet connection, please check',
    'No internet — WhatsApp features unavailable': 'No internet. WhatsApp features are unavailable',
    
    // Recipient Busy
    'Line is busy': 'The line is busy, please try again later',
    'Recipient busy': 'The line is busy, please try again later',
    
    // Call not answered
    'Call not answered': 'Call was not answered, please try again',
    
    // SOS
    'SOS activated': 'Help is on the way, do not worry',
    
    // Permission
    'Permission required': 'Please grant permission to use the phone',
    'Permission denied': 'Please grant permission to use the phone',
    
    // Battery Warnings
    'battery_20': 'Battery is running low, please plug in the charger',
    'battery_10': 'Battery is very low, please plug in the charger immediately',
    'battery_5': 'Battery is critical, plug in the charger now!',
    'battery_charging': 'Charging started',
    
    // Fallbacks
    'No name': 'No name',
    'No name saved': 'No name saved',
    
    // UI Navigation & Prompts
    'EasyConnect ready': 'EasyConnect is ready',
    'Voice guide turned off': 'Voice guide turned off',
    'Voice guide turned on': 'Voice guide turned on',
    'Showing Contacts Screen': 'Showing contacts screen',
    'Showing Keypad Dialer': 'Showing keypad dialer',
    'Showing Call History': 'Showing call history',
    'Contact saved.': 'Contact saved',
    'Too many attempts. Please wait.': 'Too many attempts, please wait',
    
    // WhatsApp & Voice Messages
    'WhatsApp is not installed. Cannot send message.': 'WhatsApp is not installed. Cannot send message.',
    'WhatsApp is not installed.': 'WhatsApp is not installed.',
    'Sending message': 'Sending your message, please wait',
    'Message sent': 'Message sent successfully',
    'Something went wrong. Please try again.': 'Something went wrong. Please try again.',
    'Backup failed. Please try again.': 'Backup failed. Please try again.',
    'Restore failed. Please check the backup file.': 'Restore failed. Please check the backup file.',
    'Data restored successfully': 'Data restored successfully',
    
    // Dialer gestures
    'deleted': 'Deleted',
    'cleared': 'Cleared',
    
    // SIM warning alerts
    'NO SIM CARD FOUND (Check card tray)': 'No SIM card found',
    'SIM CARD LOCKED (PIN/PUK needed)': 'SIM card is locked',
    'SIM CARD ERROR (Broken or disabled)': 'SIM card error',
    'SIM CARD DISCONNECTED': 'SIM card disconnected',
    'Warning: No SIM card found. Please check your SIM card tray.': 'No SIM card found. Please check your SIM card tray.',
    'Warning: SIM card is locked. PIN or PUK is required.': 'SIM card is locked. PIN or PUK is required.',
    'Warning: SIM card error. Your SIM card is broken or disabled.': 'SIM card error. Your SIM card is broken or disabled.',
    'Warning: SIM card disconnected.': 'SIM card disconnected.',
    
    // Incoming call announcements
    'incoming_call': 'Incoming call',
    'incoming_unknown': 'Incoming call from an unknown number',
    'call_missed': 'Call missed',
    'call_cut': 'Call ended',
    'no_sim': 'No SIM card, cannot make a call',
    'flight_mode': 'Flight mode is on, cannot make a call',
    
    // Countdowns & calling alerts
    '3': 'Three',
    '2': 'Two',
    '1': 'One',
    'This contact has no phone number saved.': 'This contact has no phone number saved.',
    
    // Layout and Permissions
    'Layout changed to Classic Mode': 'Layout changed to Classic Mode',
    'Layout changed to Modern Mode': 'Layout changed to Modern Mode',
    'Permission required to show incoming calls on screen.': 'Permission is required to show incoming calls on screen.',
    
    // Rearranging
    'Rearranging mode active. Long press and drag cards to sort.': 'Rearranging mode is active. Long press and drag cards to sort.',
    'Rearranging mode inactive.': 'Rearranging mode is inactive.',
    
    // SOS additions
    'Emergency contact not set. Ask your family to set this up.': 'Emergency contact is not set. Please ask your family to set this up.',
    'Emergency messages sent': 'Emergency messages sent',
    'No WhatsApp number saved. Making a standard phone call.': 'No WhatsApp number saved. Making a standard phone call.',
    'microphone_muted': 'Microphone is muted',
    'microphone_unmuted': 'Microphone is unmuted',
    'speaker_loud': 'Speaker is on',
    'speaker_soft': 'Speaker is off',
    'incoming_guided_unknown': 'Incoming call. Press the large green button to answer, or the red button to decline.',
  };

  static bool isStaticPhrase(String input) {
    final trimmed = input.trim();
    return _phrases.containsKey(trimmed) || _phrases.containsValue(trimmed) || trimmed.startsWith('To connect with ');
  }

  static String getSpokenPhrase(String input) {
    final trimmed = input.trim();
    if (_phrases.containsKey(trimmed)) {
      return _phrases[trimmed]!;
    }
    
    if (trimmed.startsWith('Calling ')) {
      final name = trimmed.substring('Calling '.length);
      return "Calling $name, please wait";
    }

    if (trimmed.startsWith('Placing call to ')) {
      final name = trimmed.substring('Placing call to '.length);
      return "Calling $name, please wait";
    }

    if (trimmed.startsWith('Starting video call with ')) {
      final name = trimmed.substring('Starting video call with '.length);
      return "Starting video call with $name, please wait";
    }

    if (trimmed.startsWith('To connect with ')) {
      final nameEndIndex = trimmed.indexOf(', tap the green button');
      if (nameEndIndex != -1) {
        final name = trimmed.substring('To connect with '.length, nameEndIndex);
        return "To connect with $name, tap the green button for a phone call, the blue button for a video call, or the orange button for a voice message.";
      }
    }

    if (trimmed.startsWith('incoming_known:')) {
      final name = trimmed.substring('incoming_known:'.length);
      return "Incoming call from $name";
    }

    if (trimmed.startsWith('second_incoming:')) {
      final name = trimmed.substring('second_incoming:'.length);
      return "Another incoming call from $name";
    }

    if (trimmed.startsWith('No WhatsApp number saved for ')) {
      final name = trimmed.substring('No WhatsApp number saved for '.length);
      final cleanedName = name.endsWith('.') ? name.substring(0, name.length - 1) : name;
      return "No WhatsApp number saved for $cleanedName";
    }

    if (trimmed.startsWith('Emergency message sent via WhatsApp to ')) {
      final name = trimmed.substring('Emergency message sent via WhatsApp to '.length);
      final cleanedName = name.endsWith('.') ? name.substring(0, name.length - 1) : name;
      return "Emergency message sent via WhatsApp to $cleanedName";
    }
    if (trimmed.startsWith('Emergency SMS sent to ')) {
      final name = trimmed.substring('Emergency SMS sent to '.length);
      final cleanedName = name.endsWith('.') ? name.substring(0, name.length - 1) : name;
      return "Emergency SMS sent to $cleanedName";
    }

    if (trimmed.startsWith('Sent message to ')) {
      final name = trimmed.substring('Sent message to '.length);
      return "Sent message to $name";
    }
    if (trimmed.startsWith('incoming_guided_known:')) {
      final name = trimmed.substring('incoming_guided_known:'.length);
      return "Incoming call from $name. Press the large green button to answer, or the red button to decline.";
    }

    return trimmed;
  }
}

class TTSService {
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final HttpClient _httpClient = HttpClient();
  String? _currentLanguage;
  int _activeSpeechId = 0;
  double? _lastVolume;

  TTSService() {
    _initCompletionHandlers();
  }

  void _initCompletionHandlers() {
    _flutterTts.setCompletionHandler(() async {
      await _flutterTts.setVolume(1.0);
    });
    _flutterTts.setErrorHandler((msg) async {
      await _flutterTts.setVolume(1.0);
      debugPrint('TTS Error: $msg');
    });
  }

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
    final speechId = ++_activeSpeechId;
    
    // Stop any currently playing audio/TTS first to prevent overlapping sounds
    // We trigger _stopHardware() without awaiting it so native hardware stops instantly
    unawaited(_stopHardware());

    unawaited(() async {
      try {
        final settingsBox = Hive.isBoxOpen('settings') ? Hive.box<AppSettings>('settings') : null;
        String languageCode = forceLanguage ?? 'en';
        if (forceLanguage == null && settingsBox != null && settingsBox.isNotEmpty) {
          final settings = settingsBox.values.first;
          if (!settings.voiceEnabled) {
            return;
          }
          languageCode = settings.language;
        }

        if (speechId != _activeSpeechId) return;

        String textToSpeak = text;
        if (languageCode == 'te') {
          textToSpeak = TeluguPhrases.getSpokenPhrase(text);
        } else if (languageCode == 'hi') {
          textToSpeak = HindiPhrases.getSpokenPhrase(text);
        } else if (languageCode == 'en') {
          textToSpeak = EnglishPhrases.getSpokenPhrase(text);
        }

        if (languageCode == 'te' || languageCode == 'hi' || languageCode == 'en') {
          final settings = settingsBox != null && settingsBox.isNotEmpty ? settingsBox.values.first : null;
          final apiKey = settings?.activeAzureSpeechSubscriptionKey ?? '';
          final region = settings?.activeAzureSpeechRegion ?? 'eastus';
          final voiceName = languageCode == 'te'
              ? (settings?.activeAzureSpeechTeluguVoice ?? 'te-IN-ShrutiNeural')
              : (languageCode == 'hi'
                  ? (settings?.activeAzureSpeechHindiVoice ?? 'hi-IN-SwaraNeural')
                  : (settings?.activeAzureSpeechEnglishVoice ?? 'en-IN-NeerjaNeural'));

          if (apiKey.isNotEmpty) {
            try {
              final dir = await getApplicationDocumentsDirectory();
              final cacheFolder = Directory('${dir.path}/tts_cache');
              if (!await cacheFolder.exists()) {
                await cacheFolder.create(recursive: true);
              }

              final fileName = 'azure_${voiceName}_${textToSpeak.hashCode}.mp3';
              final file = File('${cacheFolder.path}/$fileName');

              if (await file.exists()) {
                if (speechId == _activeSpeechId) {
                  await _audioPlayer.play(DeviceFileSource(file.path), volume: isDuringActiveCall ? 0.25 : 1.0);
                }
                return;
              }

              if (speechId != _activeSpeechId) return;

              // File is not cached.
              // 1. Immediately play via local system TTS so there is no network delay
              await _speakViaSystemTts(textToSpeak, languageCode, isDuringActiveCall);

              if (speechId != _activeSpeechId) return;

              // 2. Fetch from Azure in the background to cache for next time
              String xmlLang = 'en-US';
              final voiceParts = voiceName.split('-');
              if (voiceParts.length >= 2) {
                xmlLang = '${voiceParts[0]}-${voiceParts[1]}';
              } else {
                xmlLang = languageCode == 'te' ? 'te-IN' : (languageCode == 'hi' ? 'hi-IN' : 'en-US');
              }
              _cacheAzureSpeechInBackground(file, textToSpeak, voiceName, xmlLang, apiKey, region);
              return;
            } catch (e) {
              debugPrint('Cache/Request Azure TTS failed: $e');
            }
          }
        }

        final useOfflineTts = useSystemTts;

        if (languageCode == 'hi' && !useOfflineTts) {
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
              if (speechId == _activeSpeechId) {
                // Play cached offline native voice file
                await _audioPlayer.play(DeviceFileSource(file.path), volume: isDuringActiveCall ? 0.25 : 1.0);
              }
              return;
            }

            if (speechId != _activeSpeechId) return;

            // File is not cached.
            // 1. Immediately play via local system TTS so there is no network delay
            await _speakViaSystemTts(textToSpeak, languageCode, isDuringActiveCall);

            if (speechId != _activeSpeechId) return;

            // 2. Fetch from Google Translate in the background to cache for next time
            _cacheGoogleTranslateSpeechInBackground(file, textToSpeak, languageCode);
            return;
          } catch (e) {
            debugPrint('Cache/Connectivity TTS play failed: $e');
          }
        }

        if (speechId != _activeSpeechId) return;

        // Standard Fallback: System Offline TTS
        await _speakViaSystemTts(textToSpeak, languageCode, isDuringActiveCall);
      } catch (e) {
        debugPrint('Error in non-blocking speak task: $e');
      }
    }());
  }

  Future<void> _speakViaSystemTts(String textToSpeak, String languageCode, bool isDuringActiveCall) async {
    try {
      await init(languageCode: languageCode).timeout(
        const Duration(seconds: 1),
        onTimeout: () => debugPrint('TTS init timed out'),
      );
      
      final targetVolume = isDuringActiveCall ? 0.25 : 1.0;
      if (_lastVolume != targetVolume) {
        await _flutterTts.setVolume(targetVolume).timeout(
          const Duration(milliseconds: 300),
          onTimeout: () => debugPrint('TTS setVolume timed out'),
        );
        _lastVolume = targetVolume;
      }

      await _flutterTts.speak(textToSpeak).timeout(
        const Duration(seconds: 2),
        onTimeout: () => debugPrint('TTS speak timed out'),
      );
    } catch (e) {
      debugPrint('Error speaking via FlutterTts in helper: $e');
    }
  }

  void _cacheAzureSpeechInBackground(File file, String textToSpeak, String voiceName, String xmlLang, String apiKey, String region) {
    Future(() async {
      try {
        final url = 'https://$region.tts.speech.microsoft.com/cognitiveservices/v1';
        final request = await _httpClient.postUrl(Uri.parse(url))
            .timeout(const Duration(seconds: 5));
        request.headers.set('Ocp-Apim-Subscription-Key', apiKey);
        request.headers.set('Content-Type', 'application/ssml+xml');
        request.headers.set('X-Microsoft-OutputFormat', 'audio-24khz-96kbitrate-mono-mp3');
        request.headers.set('User-Agent', 'EasyConnect');

        final escapedText = _escapeSsml(textToSpeak);
        final ssmlBody = "<speak version='1.0' xml:lang='$xmlLang'><voice xml:lang='$xmlLang' name='$voiceName'>$escapedText</voice></speak>";

        final bodyBytes = utf8.encode(ssmlBody);
        request.headers.set('content-length', bodyBytes.length.toString());
        request.add(bodyBytes);

        final response = await request.close()
            .timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final bytes = await response.fold<List<int>>([], (p, e) => p..addAll(e))
              .timeout(const Duration(seconds: 5));
          await file.writeAsBytes(bytes);
          debugPrint('Cached Azure TTS in background: ${file.path}');
        } else {
          debugPrint('Failed background download of Azure TTS. Status: ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('Failed background request of Azure TTS: $e');
      }
    });
  }

  void _cacheGoogleTranslateSpeechInBackground(File file, String textToSpeak, String languageCode) {
    Future(() async {
      try {
        final connectivityResult = await Connectivity().checkConnectivity();
        final hasInternet = !connectivityResult.contains(ConnectivityResult.none);
        if (!hasInternet) return;

        final url = 'https://translate.google.com/translate_tts?ie=UTF-8&tl=$languageCode&client=tw-ob&q=${Uri.encodeComponent(textToSpeak)}';
        final request = await _httpClient.getUrl(Uri.parse(url))
            .timeout(const Duration(seconds: 5));
        final response = await request.close()
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final bytes = await response.fold<List<int>>([], (p, e) => p..addAll(e))
              .timeout(const Duration(seconds: 5));
          await file.writeAsBytes(bytes);
          debugPrint('Cached Google Translate TTS in background: ${file.path}');
        }
      } catch (e) {
        debugPrint('Failed background download of Translate TTS: $e');
      }
    });
  }

  Future<void> stop() async {
    _activeSpeechId++;
    await _stopHardware();
  }

  Future<void> _stopHardware() async {
    try {
      final List<Future<dynamic>> stopFutures = [
        _flutterTts.stop().timeout(
          const Duration(milliseconds: 300),
          onTimeout: () {
            debugPrint('TTS stop timed out');
            return null;
          },
        ),
        _audioPlayer.stop().timeout(
          const Duration(milliseconds: 300),
          onTimeout: () {
            debugPrint('AudioPlayer stop timed out');
            return null;
          },
        ),
      ];
      await Future.wait(stopFutures);
    } catch (e) {
      debugPrint('Error stopping TTS/AudioPlayer hardware: $e');
    }
  }

  String _escapeSsml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  Future<String?> testConnection({
    required String apiKey,
    required String region,
    required String voiceName,
    required String languageCode,
  }) async {
    if (apiKey.isEmpty) {
      return 'Subscription Key cannot be empty';
    }
    if (region.isEmpty) {
      return 'Region cannot be empty';
    }
    final url = 'https://$region.tts.speech.microsoft.com/cognitiveservices/v1';
    try {
      final request = await _httpClient.postUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      request.headers.set('Ocp-Apim-Subscription-Key', apiKey);
      request.headers.set('Content-Type', 'application/ssml+xml');
      request.headers.set('X-Microsoft-OutputFormat', 'audio-24khz-96kbitrate-mono-mp3');
      request.headers.set('User-Agent', 'EasyConnect');

      String xmlLang = 'en-US';
      final voiceParts = voiceName.split('-');
      if (voiceParts.length >= 2) {
        xmlLang = '${voiceParts[0]}-${voiceParts[1]}';
      } else {
        xmlLang = languageCode == 'te' ? 'te-IN' : (languageCode == 'hi' ? 'hi-IN' : 'en-US');
      }
      final testText = languageCode == 'te'
          ? 'ఈజీ కనెక్ట్ వాయిస్ టెస్ట్ విజయవంతమైంది.'
          : (languageCode == 'hi' ? 'ईज़ीकनेक्ट वॉयस टेस्ट सफल रहा।' : 'EasyConnect voice test successful.');
      final ssmlBody = "<speak version='1.0' xml:lang='$xmlLang'><voice xml:lang='$xmlLang' name='$voiceName'>$testText</voice></speak>";

      final bodyBytes = utf8.encode(ssmlBody);
      request.headers.set('content-length', bodyBytes.length.toString());
      request.add(bodyBytes);

      final response = await request.close()
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final bytes = await response.fold<List<int>>([], (p, e) => p..addAll(e))
            .timeout(const Duration(seconds: 5));
        
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/azure_test.mp3');
        if (await file.exists()) {
          await file.delete();
        }
        await file.writeAsBytes(bytes);
        
        await stop();
        await _audioPlayer.play(DeviceFileSource(file.path));
        return null;
      } else {
        final responseBody = await response.transform(utf8.decoder).join()
            .timeout(const Duration(seconds: 3));
        return 'HTTP Status ${response.statusCode}: $responseBody';
      }
    } catch (e) {
      return 'Connection Error: $e';
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

  void dispose() {
    _httpClient.close();
    _audioPlayer.dispose();
  }
}

final ttsServiceProvider = Provider<TTSService>((ref) {
  final service = TTSService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});
