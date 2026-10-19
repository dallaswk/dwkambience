CREATE TABLE IF NOT EXISTS `scenes` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(64) NOT NULL,
  `type` ENUM('cutscene', 'ambience') NOT NULL,
  `group_name` VARCHAR(64) NULL DEFAULT NULL,
  `studio` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `duration_ms` INT UNSIGNED NOT NULL DEFAULT 0,
  `active` TINYINT(1) NOT NULL DEFAULT 0,
  `schedule` VARCHAR(255) NULL DEFAULT NULL,
  `entity_count` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `key_count` INT UNSIGNED NOT NULL DEFAULT 0,
  `data` LONGTEXT NOT NULL,
  `schema_version` SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  `updated_by` VARCHAR(64) NULL DEFAULT NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_scenes_type` (`type`),
  KEY `idx_scenes_group` (`group_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `scene_revisions` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `scene_id` INT UNSIGNED NOT NULL,
  `rev` INT UNSIGNED NOT NULL,
  `data` LONGTEXT NOT NULL,
  `created_by` VARCHAR(64) NULL DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_scene_rev` (`scene_id`, `rev`),
  CONSTRAINT `fk_revisions_scene` FOREIGN KEY (`scene_id`) REFERENCES `scenes` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `scene_assets` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `kind` ENUM('sound', 'set_piece', 'crowd_preset') NOT NULL,
  `name` VARCHAR(64) NOT NULL,
  `data` LONGTEXT NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_asset` (`kind`, `name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
