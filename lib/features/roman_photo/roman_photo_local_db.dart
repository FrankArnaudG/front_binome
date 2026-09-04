import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Index SQLite embarqué des romans-photo téléchargés — les BLOB image
/// eux-mêmes vivent comme fichiers dans un dossier PRIVÉ de l'app (jamais
/// dans la galerie/un dossier public, voir _pagesDir), la base ne stocke que
/// les métadonnées (quel fichier correspond à quelle page). Un fichier > 1
/// Mo stocké directement en BLOB dans une ligne SQLite fait planter
/// android.database.sqlite.CursorWindow ("Row too big to fit into
/// CursorWindow") dès qu'on relit la ligne — limite dure d'Android,
/// impossible à contourner en restant sur des BLOB via sqflite. Le résultat
/// pratique reste identique à la demande utilisateur ("enregistré en local
/// dans l'app uniquement, impossible de télécharger à l'extérieur") : ce
/// dossier est dans le stockage privé de l'app (getApplicationSupportDirectory),
/// inaccessible aux autres apps et invisible dans une galerie, exactement
/// comme le serait un BLOB — seul l'endroit exact où vivent les octets change.
class RomanPhotoLocalDb {
  RomanPhotoLocalDb._();
  static final RomanPhotoLocalDb instance = RomanPhotoLocalDb._();

  Database? _db;
  Directory? _pagesDir;

  Future<Database> _database() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final dbPath = path.join(dir, 'roman_photo.db');
    Future<void> createSchema(Database db) async {
      await db.execute('''
        CREATE TABLE downloaded_volumes (
          volume_id TEXT PRIMARY KEY,
          story_id TEXT NOT NULL,
          page_count INTEGER NOT NULL,
          downloaded_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE downloaded_pages (
          volume_id TEXT NOT NULL,
          page_index INTEGER NOT NULL,
          file_name TEXT NOT NULL,
          PRIMARY KEY (volume_id, page_index)
        )
      ''');
    }

    _db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, version) => createSchema(db),
      // v1 → v2 : `downloaded_pages.bytes` (BLOB en base) remplacé par
      // `file_name` (fichier privé, voir _pagesDirectory) — v1 faisait
      // planter android.database.sqlite.CursorWindow dès qu'une page
      // dépassait sa limite de taille par ligne. Juste un cache de
      // téléchargement, rien à préserver : on repart d'un schéma propre.
      onUpgrade: (db, oldVersion, newVersion) async {
        await db.execute('DROP TABLE IF EXISTS downloaded_pages');
        await db.execute('DROP TABLE IF EXISTS downloaded_volumes');
        await createSchema(db);
      },
    );
    return _db!;
  }

  Future<Directory> _pagesDirectory() async {
    if (_pagesDir != null) return _pagesDir!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(path.join(support.path, 'roman_photo_pages'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _pagesDir = dir;
    return dir;
  }

  Future<bool> isDownloaded(String volumeId) async {
    final db = await _database();
    final rows = await db.query('downloaded_volumes', where: 'volume_id = ?', whereArgs: [volumeId], limit: 1);
    return rows.isNotEmpty;
  }

  /// Vrai si AU MOINS UN tome de cette histoire est déjà téléchargé — sert à
  /// masquer le badge "Nouveau" et à afficher le repère "déjà téléchargé"
  /// sur l'étagère (voir RomanPhotoLibraryScreen._BookTile), sans avoir
  /// besoin des ids de tomes (jamais chargés pour l'étagère légère, voir
  /// RomanPhotoStory.volumes) : `downloaded_volumes.story_id` suffit.
  Future<bool> isStoryDownloaded(String storyId) async {
    final db = await _database();
    final rows = await db.query('downloaded_volumes', where: 'story_id = ?', whereArgs: [storyId], limit: 1);
    return rows.isNotEmpty;
  }

  /// Histoires ayant au moins un tome téléchargé parmi [storyIds] — un seul
  /// aller-retour pour toute l'étagère plutôt qu'une requête par tuile.
  Future<Set<String>> downloadedStoriesAmong(Iterable<String> storyIds) async {
    final ids = storyIds.toList();
    if (ids.isEmpty) return {};
    final db = await _database();
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      'downloaded_volumes',
      columns: ['story_id'],
      where: 'story_id IN ($placeholders)',
      whereArgs: ids,
    );
    return rows.map((r) => r['story_id'] as String).toSet();
  }

  /// Volumes déjà téléchargés parmi [volumeIds] — un seul aller-retour pour
  /// alimenter les badges de toute une liste de tomes plutôt qu'une requête
  /// par tome.
  Future<Set<String>> downloadedAmong(Iterable<String> volumeIds) async {
    final ids = volumeIds.toList();
    if (ids.isEmpty) return {};
    final db = await _database();
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      'downloaded_volumes',
      columns: ['volume_id'],
      where: 'volume_id IN ($placeholders)',
      whereArgs: ids,
    );
    return rows.map((r) => r['volume_id'] as String).toSet();
  }

  Future<void> savePage(String volumeId, int index, Uint8List bytes) async {
    final dir = await _pagesDirectory();
    final fileName = '${volumeId}_$index.bin';
    await File(path.join(dir.path, fileName)).writeAsBytes(bytes, flush: true);
    final db = await _database();
    await db.insert('downloaded_pages', {
      'volume_id': volumeId,
      'page_index': index,
      'file_name': fileName,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> markComplete(String volumeId, String storyId, int pageCount) async {
    final db = await _database();
    await db.insert('downloaded_volumes', {
      'volume_id': volumeId,
      'story_id': storyId,
      'page_count': pageCount,
      'downloaded_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Pages d'un tome déjà téléchargé, dans l'ordre de lecture — `null` si le
  /// tome n'est pas (ou plus) téléchargé. Un fichier manquant sur le disque
  /// (rare : app data effacée à moitié, etc.) fait considérer le tome comme
  /// non téléchargé plutôt que de planter — voir `deleteVolume` pour
  /// nettoyer l'entrée orpheline dans ce cas.
  Future<List<Uint8List>?> loadPages(String volumeId) async {
    if (!await isDownloaded(volumeId)) return null;
    final db = await _database();
    final rows = await db.query(
      'downloaded_pages',
      where: 'volume_id = ?',
      whereArgs: [volumeId],
      orderBy: 'page_index ASC',
    );
    final dir = await _pagesDirectory();
    final pages = <Uint8List>[];
    for (final row in rows) {
      final file = File(path.join(dir.path, row['file_name'] as String));
      if (!await file.exists()) {
        await deleteVolume(volumeId);
        return null;
      }
      pages.add(await file.readAsBytes());
    }
    return pages;
  }

  /// Retire un téléchargement (tome partiel après une erreur, ou suppression
  /// volontaire pour libérer de la place) — la base ET les fichiers
  /// correspondants ensemble, pour ne jamais laisser un tome marqué
  /// "téléchargé" avec des pages manquantes, ni des fichiers orphelins sur
  /// le disque.
  Future<void> deleteVolume(String volumeId) async {
    final db = await _database();
    final rows = await db.query('downloaded_pages', columns: ['file_name'], where: 'volume_id = ?', whereArgs: [volumeId]);
    final dir = await _pagesDirectory();
    for (final row in rows) {
      final file = File(path.join(dir.path, row['file_name'] as String));
      if (await file.exists()) await file.delete();
    }
    await db.delete('downloaded_pages', where: 'volume_id = ?', whereArgs: [volumeId]);
    await db.delete('downloaded_volumes', where: 'volume_id = ?', whereArgs: [volumeId]);
  }
}
