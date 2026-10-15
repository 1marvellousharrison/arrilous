/// The 36 states of Nigeria plus the Federal Capital Territory, and a list of
/// the principal cities and towns in each. Used to drive the state and
/// state-dependent city dropdowns so a location is spelled the same way every
/// time instead of being typed free-hand.
///
/// The city lists carry the well-known towns and local government headquarters
/// of each state rather than every village; they are the choices a business,
/// partner or rider is realistically going to pick.
const List<String> nigeriaStates = <String>[
  'Abia',
  'Adamawa',
  'Akwa Ibom',
  'Anambra',
  'Bauchi',
  'Bayelsa',
  'Benue',
  'Borno',
  'Cross River',
  'Delta',
  'Ebonyi',
  'Edo',
  'Ekiti',
  'Enugu',
  'Federal Capital Territory',
  'Gombe',
  'Imo',
  'Jigawa',
  'Kaduna',
  'Kano',
  'Katsina',
  'Kebbi',
  'Kogi',
  'Kwara',
  'Lagos',
  'Nasarawa',
  'Niger',
  'Ogun',
  'Ondo',
  'Osun',
  'Oyo',
  'Plateau',
  'Rivers',
  'Sokoto',
  'Taraba',
  'Yobe',
  'Zamfara',
];

/// Principal cities and towns, keyed by state.
const Map<String, List<String>> nigeriaCitiesByState = <String, List<String>>{
  'Abia': [
    'Aba', 'Umuahia', 'Arochukwu', 'Bende', 'Isuikwuato', 'Ohafia',
    'Umu Nneochi', 'Isiala Ngwa', 'Obingwa', 'Osisioma', 'Ugwunagbo',
    'Ukwa', 'Ikwuano', 'Igbere', 'Nkporo', 'Ariam',
  ],
  'Adamawa': [
    'Yola', 'Jimeta', 'Mubi', 'Numan', 'Ganye', 'Mayo Belwa', 'Michika',
    'Hong', 'Gombi', 'Guyuk', 'Shelleng', 'Song', 'Fufore', 'Demsa',
    'Lamurde', 'Madagali', 'Toungo', 'Jada',
  ],
  'Akwa Ibom': [
    'Uyo', 'Eket', 'Ikot Ekpene', 'Oron', 'Itu', 'Ikot Abasi', 'Etinan',
    'Abak', 'Ukanafun', 'Onna', 'Mkpat Enin', 'Ini', 'Obot Akara',
    'Essien Udim', 'Ibesikpo Asutan', 'Oruk Anam',
  ],
  'Anambra': [
    'Awka', 'Onitsha', 'Nnewi', 'Ekwulobia', 'Ihiala', 'Nkpor', 'Ogidi',
    'Obosi', 'Abagana', 'Agulu', 'Aguleri', 'Umunze', 'Uli', 'Nteje',
    'Otuocha', 'Atani', 'Ozubulu',
  ],
  'Bauchi': [
    'Bauchi', 'Azare', 'Misau', 'Jama\'are', 'Katagum', 'Ningi',
    'Tafawa Balewa', 'Dass', 'Bogoro', 'Gamawa', 'Shira', 'Darazo',
    'Toro', 'Alkaleri', 'Kirfi', 'Zaki',
  ],
  'Bayelsa': [
    'Yenagoa', 'Ogbia', 'Brass', 'Sagbama', 'Ekeremor', 'Nembe',
    'Amassoma', 'Kaiama', 'Odi', 'Oporoma', 'Patani', 'Twon-Brass',
  ],
  'Benue': [
    'Makurdi', 'Gboko', 'Otukpo', 'Katsina-Ala', 'Vandeikya', 'Adikpo',
    'Ukum', 'Kwande', 'Guma', 'Tarka', 'Buruku', 'Agatu', 'Apa', 'Oju',
    'Obi', 'Ogbadibo', 'Okpokwu', 'Ohimini', 'Ushongo', 'Konshisha',
  ],
  'Borno': [
    'Maiduguri', 'Biu', 'Bama', 'Dikwa', 'Konduga', 'Monguno', 'Ngala',
    'Gwoza', 'Chibok', 'Askira', 'Kaga', 'Magumeri', 'Jere', 'Mafa',
    'Damboa', 'Shani', 'Hawul', 'Bayo',
  ],
  'Cross River': [
    'Calabar', 'Ogoja', 'Ikom', 'Obudu', 'Obanliku', 'Bekwarra', 'Yala',
    'Ugep', 'Akamkpa', 'Obubra', 'Boki', 'Etung', 'Biase', 'Bakassi',
    'Akpabuyo', 'Abi', 'Odukpani',
  ],
  'Delta': [
    'Asaba', 'Warri', 'Sapele', 'Ughelli', 'Agbor', 'Oleh', 'Ozoro',
    'Abraka', 'Kwale', 'Patani', 'Bomadi', 'Burutu', 'Oghara', 'Koko',
    'Effurun', 'Ekpan', 'Ogwashi-Uku', 'Ibusa', 'Issele-Uku', 'Umunede',
    'Obiaruku',
  ],
  'Ebonyi': [
    'Abakaliki', 'Afikpo', 'Onueke', 'Ezza', 'Ishielu', 'Ikwo',
    'Izzi', 'Ohaukwu', 'Ivo', 'Ohaozara', 'Onicha', 'Ishieke',
    'Ntezi', 'Onuebonyi',
  ],
  'Edo': [
    'Benin City', 'Auchi', 'Ekpoma', 'Uromi', 'Igarra', 'Sabongida-Ora',
    'Agenebode', 'Iguobazuwa', 'Abudu', 'Fugar', 'Ubiaja', 'Ewu',
    'Irrua', 'Opoji', 'Uzebba', 'Sobe', 'Okada', 'Siluko',
  ],
  'Ekiti': [
    'Ado-Ekiti', 'Ikere-Ekiti', 'Ikole-Ekiti', 'Ijero-Ekiti',
    'Efon-Alaaye', 'Omuo-Ekiti', 'Aramoko-Ekiti', 'Emure-Ekiti',
    'Ise-Ekiti', 'Ode-Ekiti', 'Itapa-Ekiti', 'Oye-Ekiti', 'Ido-Ekiti',
    'Otun-Ekiti', 'Ifaki-Ekiti', 'Ilupeju-Ekiti',
  ],
  'Enugu': [
    'Enugu', 'Nsukka', 'Oji River', 'Awgu', 'Udi', 'Agbani', 'Ogbede',
    'Enugu-Ezike', 'Obollo-Afor', 'Emene', 'Ndeaboh', 'Amagunze',
    'Ibagwa', 'Nike', 'Amechi',
  ],
  'Federal Capital Territory': [
    'Abuja', 'Gwagwalada', 'Kuje', 'Kwali', 'Abaji', 'Bwari', 'Nyanya',
    'Karu', 'Lugbe', 'Wuse', 'Maitama', 'Asokoro', 'Garki', 'Jabi',
    'Kubwa', 'Zuba', 'Lokogoma', 'Galadimawa',
  ],
  'Gombe': [
    'Gombe', 'Kaltungo', 'Billiri', 'Dukku', 'Bajoga', 'Nafada', 'Deba',
    'Yamaltu', 'Akko', 'Kwami', 'Funakaye', 'Balanga', 'Shongom',
  ],
  'Imo': [
    'Owerri', 'Orlu', 'Okigwe', 'Mbaise', 'Oguta', 'Nkwerre', 'Mgbidi',
    'Ihitte', 'Agbaja', 'Isu', 'Oru', 'Mbaitoli', 'Ngor Okpala',
    'Ohaji/Egbema', 'Emekuku', 'Ideato', 'Onuimo', 'Obowo',
    'Ehime Mbano',
  ],
  'Jigawa': [
    'Dutse', 'Hadejia', 'Gumel', 'Birnin Kudu', 'Ringim', 'Kazaure',
    'Jahun', 'Kafin Hausa', 'Roni', 'Babura', 'Maigatari', 'Gwaram',
    'Garki', 'Miga', 'Kaugama', 'Mallam Madori', 'Sule Tankarkar',
  ],
  'Kaduna': [
    'Kaduna', 'Zaria', 'Kafanchan', 'Zonkwa', 'Kagoro', 'Saminaka',
    'Soba', 'Makarfi', 'Ikara', 'Kubau', 'Kudan', 'Sabon Gari',
    'Birnin Gwari', 'Kachia', 'Kaura', 'Lere', 'Chikun', 'Kajuru',
    'Giwa',
  ],
  'Kano': [
    'Kano', 'Wudil', 'Gaya', 'Dambatta', 'Rano', 'Bichi', 'Karaye',
    'Sumaila', 'Dawakin Kudu', 'Dawakin Tofa', 'Minjibir', 'Gwale',
    'Bebeji', 'Kura', 'Garun Mallam', 'Ajingi', 'Kiru', 'Tudun Wada',
  ],
  'Katsina': [
    'Katsina', 'Daura', 'Funtua', 'Malumfashi', 'Dutsin-Ma', 'Kankia',
    'Jibia', 'Mani', 'Mashi', 'Zango', 'Rimi', 'Kurfi', 'Batagarawa',
    'Bakori', 'Danja', 'Kafur', 'Musawa', 'Matazu', 'Kusada', 'Ingawa',
  ],
  'Kebbi': [
    'Birnin Kebbi', 'Argungu', 'Yauri', 'Zuru', 'Jega', 'Bunza',
    'Kamba', 'Kalgo', 'Gwandu', 'Aliero', 'Sakaba', 'Bagudo', 'Augie',
    'Arewa', 'Fakai', 'Danko-Wasagu', 'Maiyama', 'Suru',
  ],
  'Kogi': [
    'Lokoja', 'Okene', 'Idah', 'Anyigba', 'Kabba', 'Ankpa', 'Egbe',
    'Isanlu', 'Ogaminana', 'Dekina', 'Ajaokuta', 'Koton Karfe',
    'Obajana', 'Ogori', 'Mopa', 'Iyara', 'Bassa',
  ],
  'Kwara': [
    'Ilorin', 'Offa', 'Omu-Aran', 'Patigi', 'Kaiama', 'Jebba', 'Kiama',
    'Share', 'Erin-Ile', 'Oke-Ode', 'Bacita', 'Afon', 'Alapa', 'Esie',
    'Oro', 'Iloffa', 'Odo-Owa', 'Lafiagi', 'Tsaragi',
  ],
  'Lagos': [
    'Ikeja', 'Lagos Island', 'Lekki', 'Victoria Island', 'Ikoyi',
    'Surulere', 'Yaba', 'Mushin', 'Oshodi', 'Isolo', 'Ikorodu',
    'Badagry', 'Epe', 'Agege', 'Alimosho', 'Apapa', 'Ajah', 'Festac',
    'Ijesha', 'Ketu', 'Ojota', 'Maryland', 'Ogba', 'Ojo', 'Amuwo',
    'Ibeju-Lekki', 'Eti-Osa', 'Ifako-Ijaiye', 'Somolu', 'Kosofe',
  ],
  'Nasarawa': [
    'Lafia', 'Keffi', 'Akwanga', 'Karu', 'Nasarawa', 'Wamba', 'Doma',
    'Awe', 'Obi', 'Keana', 'Toto', 'Kokona', 'Eggon', 'Adogi',
  ],
  'Niger': [
    'Minna', 'Bida', 'Suleja', 'Kontagora', 'Lapai', 'New Bussa',
    'Kagara', 'Rijau', 'Zungeru', 'Wushishi', 'Mokwa', 'Agaie',
    'Kutigi', 'Enagi', 'Lemu', 'Paiko', 'Bosso', 'Chanchaga', 'Gurara',
    'Munya', 'Magama',
  ],
  'Ogun': [
    'Abeokuta', 'Sagamu', 'Ijebu-Ode', 'Ota', 'Ilaro', 'Ijebu-Igbo',
    'Ifo', 'Mowe', 'Ibafo', 'Odeda', 'Obantoko', 'Ayetoro', 'Imeko',
    'Ago-Iwoye', 'Iperu', 'Isara', 'Ogere', 'Wasimi', 'Ijebu-Mushin',
    'Oru', 'Ikenne',
  ],
  'Ondo': [
    'Akure', 'Ondo City', 'Ore', 'Okitipupa', 'Ikare', 'Owo', 'Idanre',
    'Oka', 'Isua', 'Ise', 'Emure-Ile', 'Ugbe', 'Aiyede', 'Ilara',
    'Ipele', 'Akungba', 'Supare', 'Arigidi', 'Ode-Irele', 'Igbotako',
  ],
  'Osun': [
    'Osogbo', 'Ile-Ife', 'Ilesa', 'Ede', 'Iwo', 'Ikirun',
    'Ila Orangun', 'Ejigbo', 'Ikire', 'Apomu', 'Gbongan', 'Ipetumodu',
    'Modakeke', 'Ifon', 'Okuku', 'Inisa', 'Oke-Ila', 'Otan Ayegbaju',
    'Erin-Osun', 'Iragbiji',
  ],
  'Oyo': [
    'Ibadan', 'Ogbomoso', 'Oyo', 'Iseyin', 'Saki', 'Igboho', 'Kisi',
    'Eruwa', 'Igbo-Ora', 'Lanlate', 'Awe', 'Fiditi', 'Okeho', 'Iganna',
    'Iwere-Ile', 'Tede', 'Ago-Amodu', 'Maya', 'Otu', 'Ilora',
  ],
  'Plateau': [
    'Jos', 'Bukuru', 'Vom', 'Pankshin', 'Shendam', 'Barkin Ladi',
    'Kuru', 'Mangu', 'Bokkos', 'Langtang', 'Wase', 'Dengi', 'Amper',
    'Kanam', 'Riyom', 'Rukuba', 'Farin Gada',
  ],
  'Rivers': [
    'Port Harcourt', 'Bonny', 'Eleme', 'Okrika', 'Bori', 'Ahoada',
    'Omoku', 'Degema', 'Abonnema', 'Opobo', 'Andoni', 'Etche',
    'Ikwerre', 'Elele', 'Isiokpo', 'Rumuokoro', 'Onne', 'Ubima',
    'Oyigbo', 'Tai', 'Gokana', 'Khana', 'Emohua',
  ],
  'Sokoto': [
    'Sokoto', 'Tambuwal', 'Bodinga', 'Ilela', 'Gwadabawa', 'Rabah',
    'Dange', 'Wurno', 'Yabo', 'Silame', 'Binji', 'Kware', 'Wamako',
    'Shagari', 'Goronyo', 'Sabon Birni', 'Isa', 'Gada', 'Tureta',
    'Kebbe', 'Tangaza', 'Gudu',
  ],
  'Taraba': [
    'Jalingo', 'Wukari', 'Bali', 'Serti', 'Takum', 'Donga', 'Ibi',
    'Baissa', 'Gembu', 'Sunkani', 'Mutum Biyu', 'Lau', 'Karim Lamido',
    'Zing', 'Yorro', 'Ardo Kola',
  ],
  'Yobe': [
    'Damaturu', 'Potiskum', 'Gashua', 'Nguru', 'Geidam', 'Buni Yadi',
    'Fika', 'Fune', 'Nangere', 'Gujba', 'Gulani', 'Machina',
    'Yusufari', 'Karasuwa', 'Jakusko', 'Tarmuwa', 'Bade',
  ],
  'Zamfara': [
    'Gusau', 'Kaura Namoda', 'Talata Mafara', 'Anka', 'Tsafe',
    'Bungudu', 'Maru', 'Bukkuyum', 'Gummi', 'Shinkafi', 'Zurmi',
    'Maradun', 'Bakura', 'Birnin Magaji',
  ],
};

/// The cities and towns that belong to [state], or an empty list when the
/// state is unknown (so a dependent dropdown simply has nothing to offer).
List<String> citiesForState(String? state) {
  if (state == null) return const <String>[];
  return nigeriaCitiesByState[state] ?? const <String>[];
}
