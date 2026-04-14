import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const root = process.cwd();
const searchRoots = ["apps", "packages", "frontend"];

const projects = new Map();

const constraints = [
  {
    sourceTag: "type:package",
    allowedTags: ["type:package"],
    description: "packages may depend only on packages"
  },
  {
    sourceTag: "type:frontend",
    allowedTags: ["type:frontend", "type:package"],
    description: "frontend may depend only on frontend/packages"
  },
  {
    sourceTag: "type:app",
    allowedTags: ["type:app", "type:package"],
    description: "apps may depend only on apps/packages"
  }
];

function visit(dir) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const stat = statSync(full);
    if (stat.isDirectory()) {
      visit(full);
      continue;
    }
    if (entry !== "project.json") continue;

    const parsed = JSON.parse(readFileSync(full, "utf8"));
    if (!parsed.name) {
      throw new Error(`Missing project name in ${relative(root, full)}`);
    }
    projects.set(parsed.name, {
      path: relative(root, full),
      tags: Array.isArray(parsed.tags) ? parsed.tags : [],
      deps: Array.isArray(parsed.implicitDependencies) ? parsed.implicitDependencies : []
    });
  }
}

for (const searchRoot of searchRoots) {
  const abs = join(root, searchRoot);
  try {
    visit(abs);
  } catch {
    // Ignore roots that do not exist.
  }
}

const violations = [];

for (const [projectName, project] of projects.entries()) {
  for (const dep of project.deps) {
    const depProject = projects.get(dep);
    if (!depProject) {
      violations.push(`${projectName} -> ${dep}: dependency project not found`);
      continue;
    }

    for (const rule of constraints) {
      if (!project.tags.includes(rule.sourceTag)) continue;
      const isAllowed = depProject.tags.some((tag) => rule.allowedTags.includes(tag));
      if (!isAllowed) {
        violations.push(
          `${projectName} (${rule.sourceTag}) -> ${dep} breaks rule: ${rule.description}`
        );
      }
    }
  }
}

if (violations.length > 0) {
  console.error("Boundary violations detected:");
  for (const violation of violations) {
    console.error(`- ${violation}`);
  }
  process.exit(1);
}

console.log("Boundary checks passed.");
