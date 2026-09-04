import 'dart:math';

/// Copie Dart de `app/Support/PictionaryWordBank.php` — mêmes 40 concepts
/// dans les 12 langues (voir le fichier PHP pour le détail), utilisée par
/// les modes présentiel (Nearby Connections et pass-and-play), qui ne
/// passent jamais par le serveur pendant la partie.
class PictionaryWordBank {
  static const Map<String, List<String>> _words = {
    'fr': ['Chat', 'Chien', 'Maison', 'Soleil', 'Arbre', 'Voiture', 'Poisson', 'Oiseau', 'Fleur', 'Étoile', 'Lune', 'Nuage', 'Pizza', 'Gâteau', 'Livre', 'Chapeau', 'Lunettes', 'Parapluie', 'Vélo', 'Bateau', 'Avion', 'Téléphone', 'Horloge', 'Cœur', 'Robot', 'Fantôme', 'Serpent', 'Éléphant', 'Papillon', 'Guitare', 'Ballon', 'Cadeau', 'Échelle', 'Clé', 'Bougie', 'Couronne', 'Fusée', 'Pomme', 'Glace', 'Parapluie renversé'],
    'en': ['Cat', 'Dog', 'House', 'Sun', 'Tree', 'Car', 'Fish', 'Bird', 'Flower', 'Star', 'Moon', 'Cloud', 'Pizza', 'Cake', 'Book', 'Hat', 'Glasses', 'Umbrella', 'Bicycle', 'Boat', 'Airplane', 'Phone', 'Clock', 'Heart', 'Robot', 'Ghost', 'Snake', 'Elephant', 'Butterfly', 'Guitar', 'Balloon', 'Gift', 'Ladder', 'Key', 'Candle', 'Crown', 'Rocket', 'Apple', 'Ice cream', 'Broken umbrella'],
    'de': ['Katze', 'Hund', 'Haus', 'Sonne', 'Baum', 'Auto', 'Fisch', 'Vogel', 'Blume', 'Stern', 'Mond', 'Wolke', 'Pizza', 'Kuchen', 'Buch', 'Hut', 'Brille', 'Regenschirm', 'Fahrrad', 'Boot', 'Flugzeug', 'Telefon', 'Uhr', 'Herz', 'Roboter', 'Gespenst', 'Schlange', 'Elefant', 'Schmetterling', 'Gitarre', 'Luftballon', 'Geschenk', 'Leiter', 'Schlüssel', 'Kerze', 'Krone', 'Rakete', 'Apfel', 'Eis', 'Kaputter Regenschirm'],
    'es': ['Gato', 'Perro', 'Casa', 'Sol', 'Árbol', 'Coche', 'Pez', 'Pájaro', 'Flor', 'Estrella', 'Luna', 'Nube', 'Pizza', 'Pastel', 'Libro', 'Sombrero', 'Gafas', 'Paraguas', 'Bicicleta', 'Barco', 'Avión', 'Teléfono', 'Reloj', 'Corazón', 'Robot', 'Fantasma', 'Serpiente', 'Elefante', 'Mariposa', 'Guitarra', 'Globo', 'Regalo', 'Escalera', 'Llave', 'Vela', 'Corona', 'Cohete', 'Manzana', 'Helado', 'Paraguas roto'],
    'zh': ['猫', '狗', '房子', '太阳', '树', '汽车', '鱼', '鸟', '花', '星星', '月亮', '云', '披萨', '蛋糕', '书', '帽子', '眼镜', '雨伞', '自行车', '船', '飞机', '电话', '时钟', '心形', '机器人', '幽灵', '蛇', '大象', '蝴蝶', '吉他', '气球', '礼物', '梯子', '钥匙', '蜡烛', '皇冠', '火箭', '苹果', '冰淇淋', '坏掉的雨伞'],
    'ar': ['قطة', 'كلب', 'منزل', 'شمس', 'شجرة', 'سيارة', 'سمكة', 'طائر', 'زهرة', 'نجمة', 'قمر', 'غيمة', 'بيتزا', 'كعكة', 'كتاب', 'قبعة', 'نظارات', 'مظلة', 'دراجة', 'قارب', 'طائرة', 'هاتف', 'ساعة', 'قلب', 'روبوت', 'شبح', 'ثعبان', 'فيل', 'فراشة', 'غيتار', 'بالون', 'هدية', 'سلم', 'مفتاح', 'شمعة', 'تاج', 'صاروخ', 'تفاحة', 'آيس كريم', 'مظلة مكسورة'],
    'id': ['Kucing', 'Anjing', 'Rumah', 'Matahari', 'Pohon', 'Mobil', 'Ikan', 'Burung', 'Bunga', 'Bintang', 'Bulan', 'Awan', 'Piza', 'Kue', 'Buku', 'Topi', 'Kacamata', 'Payung', 'Sepeda', 'Perahu', 'Pesawat', 'Telepon', 'Jam', 'Hati', 'Robot', 'Hantu', 'Ular', 'Gajah', 'Kupu-kupu', 'Gitar', 'Balon', 'Hadiah', 'Tangga', 'Kunci', 'Lilin', 'Mahkota', 'Roket', 'Apel', 'Es krim', 'Payung rusak'],
    'ru': ['Кошка', 'Собака', 'Дом', 'Солнце', 'Дерево', 'Машина', 'Рыба', 'Птица', 'Цветок', 'Звезда', 'Луна', 'Облако', 'Пицца', 'Торт', 'Книга', 'Шляпа', 'Очки', 'Зонт', 'Велосипед', 'Лодка', 'Самолёт', 'Телефон', 'Часы', 'Сердце', 'Робот', 'Привидение', 'Змея', 'Слон', 'Бабочка', 'Гитара', 'Шарик', 'Подарок', 'Лестница', 'Ключ', 'Свеча', 'Корона', 'Ракета', 'Яблоко', 'Мороженое', 'Сломанный зонт'],
    'pt': ['Gato', 'Cachorro', 'Casa', 'Sol', 'Árvore', 'Carro', 'Peixe', 'Pássaro', 'Flor', 'Estrela', 'Lua', 'Nuvem', 'Pizza', 'Bolo', 'Livro', 'Chapéu', 'Óculos', 'Guarda-chuva', 'Bicicleta', 'Barco', 'Avião', 'Telefone', 'Relógio', 'Coração', 'Robô', 'Fantasma', 'Cobra', 'Elefante', 'Borboleta', 'Violão', 'Balão', 'Presente', 'Escada', 'Chave', 'Vela', 'Coroa', 'Foguete', 'Maçã', 'Sorvete', 'Guarda-chuva quebrado'],
    'tr': ['Kedi', 'Köpek', 'Ev', 'Güneş', 'Ağaç', 'Araba', 'Balık', 'Kuş', 'Çiçek', 'Yıldız', 'Ay', 'Bulut', 'Pizza', 'Pasta', 'Kitap', 'Şapka', 'Gözlük', 'Şemsiye', 'Bisiklet', 'Tekne', 'Uçak', 'Telefon', 'Saat', 'Kalp', 'Robot', 'Hayalet', 'Yılan', 'Fil', 'Kelebek', 'Gitar', 'Balon', 'Hediye', 'Merdiven', 'Anahtar', 'Mum', 'Taç', 'Roket', 'Elma', 'Dondurma', 'Kırık şemsiye'],
    'uk': ['Кіт', 'Собака', 'Будинок', 'Сонце', 'Дерево', 'Машина', 'Риба', 'Птах', 'Квітка', 'Зірка', 'Місяць', 'Хмара', 'Піца', 'Торт', 'Книга', 'Капелюх', 'Окуляри', 'Парасолька', 'Велосипед', 'Човен', 'Літак', 'Телефон', 'Годинник', 'Серце', 'Робот', 'Привид', 'Змія', 'Слон', 'Метелик', 'Гітара', 'Кулька', 'Подарунок', 'Драбина', 'Ключ', 'Свічка', 'Корона', 'Ракета', 'Яблуко', 'Морозиво', 'Зламана парасолька'],
    'ja': ['ネコ', 'イヌ', '家', '太陽', '木', '車', '魚', '鳥', '花', '星', '月', '雲', 'ピザ', 'ケーキ', '本', '帽子', 'メガネ', '傘', '自転車', 'ボート', '飛行機', '電話', '時計', 'ハート', 'ロボット', 'おばけ', 'ヘビ', 'ゾウ', 'チョウ', 'ギター', '風船', 'プレゼント', 'はしご', '鍵', 'ろうそく', '王冠', 'ロケット', 'リンゴ', 'アイスクリーム', '壊れた傘'],
  };

  static List<String> words(String locale) => _words[locale] ?? _words['fr']!;

  static String randomWord(String locale) {
    final list = words(locale);
    return list[Random().nextInt(list.length)];
  }
}
