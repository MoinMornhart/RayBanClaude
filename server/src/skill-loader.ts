import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { c } from "./console-theme.js";
import { SERVER_ROOT } from "./env.js";

// ── Skill-Loader ────────────────────────────────────────────────────
// Sucht SKILL.md-Dateien in:
//   1. server/skills (eigene Skills des Gateways)
//   2. ~/.claude/skills
//   3. ~/.claude/plugins (rekursiv)
//   4. optional SKILL_PATHS aus der .env (Trennzeichen: path.delimiter,
//      also ";" unter Windows und ":" unter macOS/Linux; relative Pfade
//      beziehen sich auf den server-Ordner)
// Im Systemprompt stehen nur Name + Beschreibung; den vollständigen Inhalt
// lädt Claude bei Bedarf über das lokale Werkzeug "skill_laden".

export interface Skill {
  readonly name: string;
  readonly description: string;
  readonly trigger: string;
  readonly content: string;
  readonly filePath: string;
}

export interface SkillSummary {
  readonly name: string;
  readonly description: string;
  readonly trigger: string;
}

const MAX_SCAN_DEPTH = 8;
const MAX_SKILL_FILES = 500;
const MAX_SKILL_FILE_BYTES = 262_144; // 256 KB
const MAX_DESCRIPTION_LENGTH = 300;
const MAX_NAME_LENGTH = 64;
const FRONTMATTER_FENCE = "---";
const HEADING_MARK = "#";
const ELLIPSIS = "…";
const SKILL_FILE_NAMES: ReadonlySet<string> = new Set(["SKILL.md", "skill.md"]);
const SKIPPED_DIRS: ReadonlySet<string> = new Set(["node_modules", ".git"]);
const BLOCK_SCALAR_MARKERS: ReadonlySet<string> = new Set([">", "|", ">-", "|-", ">+", "|+"]);
const QUOTE_CHARS: ReadonlySet<string> = new Set(['"', "'"]);
const IGNORED_FS_ERRORS: ReadonlySet<string> = new Set(["ENOENT", "ENOTDIR"]);

/** Standard-Suchpfade (relativ zum server-Ordner bzw. Home-Verzeichnis). */
export function defaultSkillPaths(): string[] {
  const home = os.homedir();
  const extra = (process.env.SKILL_PATHS ?? "")
    .split(path.delimiter)
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => path.resolve(SERVER_ROOT, entry));
  return [
    path.join(SERVER_ROOT, "skills"),
    path.join(home, ".claude", "skills"),
    path.join(home, ".claude", "plugins"),
    ...extra,
  ];
}

function errorCode(err: unknown): string | undefined {
  return err instanceof Error && "code" in err && typeof err.code === "string"
    ? err.code
    : undefined;
}

function readDirSafe(dir: string): fs.Dirent[] {
  try {
    return fs.readdirSync(dir, { withFileTypes: true });
  } catch (err) {
    const code = errorCode(err);
    if (!code || !IGNORED_FS_ERRORS.has(code)) {
      console.warn(c.label("[Skills]") + c.warn(` Ordner nicht lesbar (${code ?? "?"}): ${dir}`));
    }
    return [];
  }
}

/** Findet rekursiv alle SKILL.md-Dateien (Symlinks werden nicht verfolgt). */
function findSkillFiles(dir: string, depth: number): string[] {
  if (depth > MAX_SCAN_DEPTH) return [];
  return readDirSafe(dir).flatMap((entry) => {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      return SKIPPED_DIRS.has(entry.name) ? [] : findSkillFiles(fullPath, depth + 1);
    }
    return entry.isFile() && SKILL_FILE_NAMES.has(entry.name) ? [fullPath] : [];
  });
}

// ── Frontmatter-Parser (minimal, ohne YAML-Abhängigkeit) ──

interface ParsedSkillFile {
  readonly frontmatter: readonly string[];
  readonly body: string;
}

function splitFrontmatter(raw: string): ParsedSkillFile {
  const lines = raw.split("\n");
  if (lines[0]?.trim() !== FRONTMATTER_FENCE) {
    return { frontmatter: [], body: raw.trim() };
  }
  const end = lines.findIndex((line, index) => index > 0 && line.trim() === FRONTMATTER_FENCE);
  if (end === -1) {
    return { frontmatter: [], body: raw.trim() };
  }
  return { frontmatter: lines.slice(1, end), body: lines.slice(end + 1).join("\n").trim() };
}

function stripQuotes(value: string): string {
  const first = value.charAt(0);
  const isQuoted = QUOTE_CHARS.has(first) && value.length > 1 && value.endsWith(first);
  return isQuoted ? value.slice(1, -1) : value;
}

/** Sammelt eingerückte Folgezeilen eines YAML-Blockskalars (">" bzw. "|"). */
function collectIndented(lines: readonly string[]): string {
  const end = lines.findIndex(
    (line) => Boolean(line.trim()) && !line.startsWith(" ") && !line.startsWith("\t")
  );
  const block = end === -1 ? lines : lines.slice(0, end);
  return block.map((line) => line.trim()).filter(Boolean).join(" ");
}

function frontmatterValue(lines: readonly string[], key: string): string {
  const prefix = `${key}:`;
  const index = lines.findIndex((line) => line.toLowerCase().startsWith(prefix));
  if (index === -1) return "";
  const inline = lines[index].slice(prefix.length).trim();
  const value = BLOCK_SCALAR_MARKERS.has(inline) ? collectIndented(lines.slice(index + 1)) : inline;
  // Escapete Zeilenumbrüche ("\n" als Text) in Leerzeichen umwandeln
  return stripQuotes(value).split("\\n").join(" ").trim();
}

function truncate(text: string, maxLength: number): string {
  return text.length > maxLength ? `${text.slice(0, maxLength - 1)}${ELLIPSIS}` : text;
}

/** Erste nicht-leere Zeile des Inhalts, ohne führende "#". */
function firstLineDescription(body: string): string {
  const firstLine = body.split("\n").find((line) => line.trim()) ?? "";
  const textStart = [...firstLine].findIndex((ch) => ch !== HEADING_MARK);
  return (textStart === -1 ? "" : firstLine.slice(textStart)).trim();
}

function parseSkillFile(filePath: string): Skill | null {
  try {
    if (fs.statSync(filePath).size > MAX_SKILL_FILE_BYTES) {
      console.warn(c.label("[Skills]") + c.warn(` Datei zu groß, übersprungen: ${filePath}`));
      return null;
    }
    // Windows-Zeilenenden vereinheitlichen, damit der Frontmatter-Parser greift
    const raw = fs.readFileSync(filePath, "utf-8").split("\r\n").join("\n");
    const { frontmatter, body } = splitFrontmatter(raw);
    const dirName = path.basename(path.dirname(filePath));
    const name = truncate(frontmatterValue(frontmatter, "name") || dirName, MAX_NAME_LENGTH);
    const description = truncate(
      frontmatterValue(frontmatter, "description") || firstLineDescription(body),
      MAX_DESCRIPTION_LENGTH
    );
    const trigger = frontmatterValue(frontmatter, "trigger") || name;
    return { name, description, trigger, content: body, filePath };
  } catch (err) {
    console.warn(c.label("[Skills]") + c.warn(` Skill nicht lesbar: ${filePath}`), err);
    return null;
  }
}

export class SkillLoader {
  private skills = new Map<string, Skill>();
  private readonly searchPaths: readonly string[];

  constructor(searchPaths: readonly string[] = defaultSkillPaths()) {
    this.searchPaths = searchPaths;
  }

  /** Durchsucht alle Suchpfade und lädt die Skills (erster Fund eines Namens gewinnt). */
  load(): void {
    console.log(c.label("[Skills]") + " Suche nach Skills...");

    const allFiles = this.searchPaths.flatMap((searchPath) => findSkillFiles(searchPath, 0));
    if (allFiles.length > MAX_SKILL_FILES) {
      console.warn(
        c.label("[Skills]") +
          c.warn(` ${allFiles.length} Skill-Dateien gefunden – nur die ersten ${MAX_SKILL_FILES} werden geladen.`)
      );
    }

    this.skills = allFiles
      .slice(0, MAX_SKILL_FILES)
      .map(parseSkillFile)
      .filter((skill): skill is Skill => skill !== null)
      .reduce((map, skill) => (map.has(skill.name) ? map : map.set(skill.name, skill)), new Map<string, Skill>());

    if (this.skills.size) {
      const names = [...this.skills.keys()].join(", ");
      console.log(
        c.label("[Skills]") + c.success(` ${this.skills.size} Skill(s) geladen: `) + c.dim(names)
      );
    } else {
      console.log(
        c.label("[Skills]") +
          c.dim(" Keine Skills gefunden (SKILL.md-Dateien in server/skills ablegen)")
      );
    }
  }

  /** Lädt die Skills neu (z. B. nach Änderungen an den Dateien). */
  reload(): void {
    const previousCount = this.skills.size;
    this.load();
    const diff = this.skills.size - previousCount;
    if (diff) {
      console.log(
        c.label("[Skills]") + ` Neu geladen: ${diff > 0 ? "+" : ""}${diff} Skill(s)`
      );
    }
  }

  getAll(): Skill[] {
    return [...this.skills.values()];
  }

  get(name: string): Skill | undefined {
    return this.skills.get(name);
  }

  /** Abschnitt für den Systemprompt: Liste der verfügbaren Skills. */
  buildSystemPromptSection(toolName: string): string {
    if (!this.skills.size) return "";
    const lines = [
      "",
      "",
      "VERFÜGBARE SKILLS:",
      `Für die folgenden Aufgaben gibt es ausführliche Anleitungen. Wenn eine Anfrage zu einem Skill passt, lade die Anleitung mit dem Werkzeug „${toolName}“ und folge ihr.`,
      "",
      ...this.getAll().map((skill) => `- ${skill.name}: ${skill.description}`),
    ];
    return lines.join("\n");
  }

  /** Vollständiger Skill-Inhalt für das Werkzeug "skill_laden". */
  getSkillPrompt(name: string): string | null {
    const skill = this.skills.get(name);
    return skill ? `[SKILL: ${skill.name}]\n${skill.content}\n[/SKILL]` : null;
  }

  get count(): number {
    return this.skills.size;
  }

  /** Übersicht für die Endpunkte /skills und /health/details. */
  getSkillList(): SkillSummary[] {
    return this.getAll().map((skill) => ({
      name: skill.name,
      description: skill.description,
      trigger: skill.trigger,
    }));
  }
}
