#!/usr/bin/env python3
"""Range's cached source-graph language server."""

import argparse
import json
import os
import pathlib
import sys
import urllib.parse
from collections import deque
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple


ROOT_DECLARATIONS = {
    "construct": "class",
    "enum": "enum",
    "extension": "class",
    "function": "function",
    "macro": "macro",
}
MEMBER_DECLARATIONS = {
    "binding": "property",
    "derived": "property",
    "let": "variable",
    "state": "variable",
}
IGNORED_DIRECTORIES = {
    ".build",
    ".git",
    ".range",
    "Bootstrap",
    "node_modules",
    "target",
}


@dataclass(frozen=True)
class Token:
    text: str
    line: int
    start: int
    end: int


@dataclass(frozen=True)
class Declaration:
    name: str
    kind: str
    uri: str
    line: int
    start: int
    end: int
    scope: int

    def location(self) -> Dict[str, object]:
        return {
            "uri": self.uri,
            "range": {
                "start": {"line": self.line, "character": self.start},
                "end": {"line": self.line, "character": self.end},
            },
        }


@dataclass(frozen=True)
class FileGraph:
    uri: str
    source: str
    signature: Tuple[int, int, int]
    tokens: Tuple[Token, ...]
    token_scopes: Tuple[int, ...]
    scope_parents: Tuple[int, ...]
    declarations: Tuple[Declaration, ...]


def path_to_uri(path: pathlib.Path) -> str:
    return path.resolve().as_uri()


def uri_to_path(uri: str) -> pathlib.Path:
    parsed = urllib.parse.urlparse(uri)
    if parsed.scheme != "file":
        raise ValueError("Range navigation currently supports file URIs")
    return pathlib.Path(urllib.parse.unquote(parsed.path))


def utf16_length(text: str) -> int:
    return len(text.encode("utf-16-le")) // 2


def codepoint_index_for_utf16(text: str, character: int) -> int:
    units = 0
    for index, scalar in enumerate(text):
        width = utf16_length(scalar)
        if units + width > character:
            return index
        units += width
    return len(text)


def tokenize(source: str) -> List[Token]:
    tokens: List[Token] = []
    line = 0
    column = 0
    index = 0

    while index < len(source):
        scalar = source[index]
        following = source[index + 1] if index + 1 < len(source) else ""
        if scalar == "\n":
            line += 1
            column = 0
            index += 1
            continue
        if scalar.isspace():
            column += utf16_length(scalar)
            index += 1
            continue
        if scalar == "/" and following == "/":
            index += 2
            column += 2
            while index < len(source) and source[index] != "\n":
                column += utf16_length(source[index])
                index += 1
            continue
        if scalar == "/" and following == "*":
            index += 2
            column += 2
            while index < len(source):
                if source[index:index + 2] == "*/":
                    index += 2
                    column += 2
                    break
                if source[index] == "\n":
                    line += 1
                    column = 0
                else:
                    column += utf16_length(source[index])
                index += 1
            continue
        if scalar in {'"', "'", "`"}:
            quote = scalar
            index += 1
            column += 1
            escaped = False
            while index < len(source):
                current = source[index]
                if current == "\n" and quote != "`":
                    break
                if current == "\n":
                    line += 1
                    column = 0
                    index += 1
                    escaped = False
                    continue
                index += 1
                column += utf16_length(current)
                if escaped:
                    escaped = False
                elif current == "\\":
                    escaped = True
                elif current == quote:
                    break
            continue
        if scalar == "_" or scalar.isalpha():
            start = column
            end_index = index + 1
            while end_index < len(source):
                candidate = source[end_index]
                if candidate != "_" and not candidate.isalnum():
                    break
                end_index += 1
            text = source[index:end_index]
            column += utf16_length(text)
            tokens.append(Token(text, line, start, column))
            index = end_index
            continue
        start = column
        column += utf16_length(scalar)
        tokens.append(Token(scalar, line, start, column))
        index += 1
    return tokens


def is_identifier(token: Token) -> bool:
    return bool(token.text) and (
        token.text[0] == "_" or token.text[0].isalpha()
    )


def file_graph(
    uri: str, source: str, signature: Tuple[int, int, int]
) -> FileGraph:
    tokens = tokenize(source)
    token_scopes: List[int] = []
    scope_parents = [-1]
    current_scope = 0
    for token in tokens:
        if token.text == "}" and current_scope != 0:
            current_scope = scope_parents[current_scope]
        token_scopes.append(current_scope)
        if token.text == "{":
            scope_parents.append(current_scope)
            current_scope = len(scope_parents) - 1

    declarations: List[Declaration] = []
    declaration_token_indexes: Set[int] = set()
    for index, token in enumerate(tokens):
        kind = ROOT_DECLARATIONS.get(token.text)
        name_index: Optional[int] = None
        if kind is not None and index + 1 < len(tokens):
            if is_identifier(tokens[index + 1]):
                name_index = index + 1
        elif token.text in MEMBER_DECLARATIONS:
            kind = MEMBER_DECLARATIONS[token.text]
            cursor = index + 1
            while cursor < len(tokens) and tokens[cursor].line == token.line:
                if tokens[cursor].text in {":", "=", "{"}:
                    break
                if is_identifier(tokens[cursor]) and tokens[cursor].text != "_":
                    name_index = cursor
                cursor += 1
        if kind is None or name_index is None:
            continue
        name = tokens[name_index]
        declarations.append(
            Declaration(
                name.text,
                kind,
                uri,
                name.line,
                name.start,
                name.end,
                token_scopes[name_index],
            )
        )
        declaration_token_indexes.add(name_index)

    return FileGraph(
        uri,
        source,
        signature,
        tuple(tokens),
        tuple(token_scopes),
        tuple(scope_parents),
        tuple(declarations),
    )


def source_files(root: pathlib.Path) -> Iterable[pathlib.Path]:
    for directory, child_directories, filenames in os.walk(str(root)):
        child_directories[:] = [
            child
            for child in child_directories
            if child not in IGNORED_DIRECTORIES
        ]
        for filename in filenames:
            if filename.endswith(".range"):
                yield pathlib.Path(directory) / filename


def workspace_node() -> str:
    return "workspace"


def file_node(uri: str) -> str:
    return "file:" + uri


def scope_node(uri: str, scope: int) -> str:
    return "scope:{}:{}".format(uri, scope)


class NavigationGraph:
    """One immutable workspace graph generation plus cached jump links."""

    def __init__(self, files: Dict[str, FileGraph], generation: int):
        self.files = files
        self.generation = generation
        self.neighbors: Dict[str, List[str]] = {workspace_node(): []}
        self.declarations_by_node: Dict[str, List[Declaration]] = {}
        self.jump_links: Dict[
            Tuple[str, int, int, str, str], Tuple[Declaration, Tuple[str, ...]]
        ] = {}
        self._build()

    def _connect(self, source: str, destination: str) -> None:
        self.neighbors.setdefault(source, []).append(destination)

    def _build(self) -> None:
        for uri in sorted(self.files):
            parsed = self.files[uri]
            file_id = file_node(uri)
            self._connect(workspace_node(), file_id)
            self._connect(file_id, workspace_node())
            self._connect(file_id, scope_node(uri, 0))
            self._connect(scope_node(uri, 0), file_id)
            for scope, parent in enumerate(parsed.scope_parents):
                node = scope_node(uri, scope)
                self.neighbors.setdefault(node, [])
                if parent >= 0:
                    self._connect(node, scope_node(uri, parent))
            for declaration in parsed.declarations:
                node = scope_node(uri, declaration.scope)
                self.declarations_by_node.setdefault(node, []).append(declaration)
        for values in self.neighbors.values():
            values.sort()
        for values in self.declarations_by_node.values():
            values.sort(key=lambda item: (item.uri, item.line, item.start))

    def token_at(
        self, uri: str, line: int, character: int
    ) -> Optional[Tuple[Token, int]]:
        parsed = self.files.get(uri)
        if parsed is None:
            return None
        for index, token in enumerate(parsed.tokens):
            if token.line == line and token.start <= character <= token.end:
                if is_identifier(token):
                    return token, parsed.token_scopes[index]
        return None

    def symbol_hint(
        self, parsed: FileGraph, token: Token
    ) -> str:
        lines = parsed.source.splitlines()
        line = lines[token.line] if token.line < len(lines) else ""
        start = codepoint_index_for_utf16(line, token.start)
        end = codepoint_index_for_utf16(line, token.end)
        if start > 0 and line[start - 1] == "@":
            return "macro"
        if line[end:].lstrip().startswith("("):
            return "type" if token.text[0].isupper() else "function"
        return "any"

    @staticmethod
    def compatible(declaration: Declaration, hint: str) -> bool:
        if hint == "macro":
            return declaration.kind == "macro"
        if hint == "type":
            return declaration.kind in {"class", "enum"}
        if hint == "function":
            return declaration.kind == "function"
        return True

    def shortest_jump(
        self, uri: str, line: int, character: int
    ) -> Optional[Declaration]:
        parsed = self.files.get(uri)
        occurrence = self.token_at(uri, line, character)
        if parsed is None or occurrence is None:
            return None
        token, scope = occurrence
        for declaration in parsed.declarations:
            if (
                declaration.line == token.line
                and declaration.start == token.start
                and declaration.end == token.end
            ):
                return declaration

        hint = self.symbol_hint(parsed, token)
        cache_key = (uri, token.line, token.start, token.text, hint)
        cached = self.jump_links.get(cache_key)
        if cached is not None:
            return cached[0]

        start_node = scope_node(uri, scope)
        queue = deque([(start_node, (start_node,))])
        visited = {start_node}
        fallback: Optional[Tuple[Declaration, Tuple[str, ...]]] = None
        while queue:
            node, path = queue.popleft()
            named = [
                declaration
                for declaration in self.declarations_by_node.get(node, [])
                if declaration.name == token.text
            ]
            compatible = [
                declaration
                for declaration in named
                if self.compatible(declaration, hint)
            ]
            if compatible:
                result = (compatible[0], path)
                self.jump_links[cache_key] = result
                return result[0]
            if named and fallback is None:
                fallback = (named[0], path)
            for neighbor in self.neighbors.get(node, []):
                if neighbor not in visited:
                    visited.add(neighbor)
                    queue.append((neighbor, path + (neighbor,)))

        if fallback is not None:
            self.jump_links[cache_key] = fallback
            return fallback[0]
        return None


class WorkspaceIndex:
    def __init__(self, root: pathlib.Path):
        self.root = root.resolve()
        self.open_documents: Dict[str, Tuple[str, int]] = {}
        self.file_cache: Dict[str, FileGraph] = {}
        self.active_signatures: Dict[str, Tuple[int, int, int]] = {}
        self.cached_graph: Optional[NavigationGraph] = None
        self.generation = 0
        self.open_revision = 0

    def open_document(self, uri: str, source: str) -> None:
        self.open_revision += 1
        self.open_documents[uri] = (source, self.open_revision)

    def close_document(self, uri: str) -> None:
        if uri in self.open_documents:
            del self.open_documents[uri]
            self.cached_graph = None

    def graph(self) -> NavigationGraph:
        signatures: Dict[str, Tuple[int, int, int]] = {}
        paths: Dict[str, pathlib.Path] = {}
        for path in source_files(self.root):
            uri = path_to_uri(path)
            paths[uri] = path
            if uri in self.open_documents:
                signatures[uri] = (1, self.open_documents[uri][1], 0)
                continue
            try:
                metadata = path.stat()
            except OSError:
                continue
            signatures[uri] = (0, metadata.st_mtime_ns, metadata.st_size)
        for uri, (_, revision) in self.open_documents.items():
            signatures[uri] = (1, revision, 0)

        if self.cached_graph is not None and signatures == self.active_signatures:
            return self.cached_graph

        files: Dict[str, FileGraph] = {}
        for uri, signature in signatures.items():
            cached = self.file_cache.get(uri)
            if cached is not None and cached.signature == signature:
                files[uri] = cached
                continue
            if uri in self.open_documents:
                source = self.open_documents[uri][0]
            else:
                try:
                    source = paths[uri].read_text(encoding="utf-8")
                except (OSError, UnicodeError):
                    continue
            parsed = file_graph(uri, source, signature)
            self.file_cache[uri] = parsed
            files[uri] = parsed

        for stale_uri in self.file_cache.keys() - signatures.keys():
            del self.file_cache[stale_uri]
        self.generation += 1
        self.active_signatures = signatures
        self.cached_graph = NavigationGraph(files, self.generation)
        return self.cached_graph

    def definition(
        self, uri: str, line_number: int, utf16_character: int
    ) -> Optional[Declaration]:
        return self.graph().shortest_jump(uri, line_number, utf16_character)


class LanguageServer:
    def __init__(self):
        self.index = WorkspaceIndex(pathlib.Path.cwd())
        self.shutdown_requested = False

    def handle(self, message: Dict[str, object]) -> Optional[Dict[str, object]]:
        method = message.get("method")
        request_id = message.get("id")
        params = message.get("params") or {}
        if method == "initialize":
            root_uri = params.get("rootUri")
            folders = params.get("workspaceFolders") or []
            if not root_uri and folders:
                root_uri = folders[0].get("uri")
            if root_uri:
                self.index = WorkspaceIndex(uri_to_path(root_uri))
            return self.response(
                request_id,
                {
                    "capabilities": {
                        "textDocumentSync": 1,
                        "definitionProvider": True,
                    },
                    "serverInfo": {
                        "name": "range-language-server",
                        "version": "0.2.0",
                    },
                },
            )
        if method == "shutdown":
            self.shutdown_requested = True
            return self.response(request_id, None)
        if method == "exit":
            raise SystemExit(0 if self.shutdown_requested else 1)
        if method in {"textDocument/didOpen", "textDocument/didChange"}:
            document = params["textDocument"]
            if method == "textDocument/didOpen":
                source = document["text"]
            else:
                changes = params.get("contentChanges") or []
                if not changes:
                    return None
                source = changes[-1]["text"]
            self.index.open_document(document["uri"], source)
            return None
        if method == "textDocument/didClose":
            self.index.close_document(params["textDocument"]["uri"])
            return None
        if method == "textDocument/definition":
            document = params["textDocument"]
            position = params["position"]
            declaration = self.index.definition(
                document["uri"], position["line"], position["character"]
            )
            return self.response(
                request_id, declaration.location() if declaration else None
            )
        if request_id is not None:
            return {
                "jsonrpc": "2.0",
                "id": request_id,
                "error": {"code": -32601, "message": "Method not found"},
            }
        return None

    @staticmethod
    def response(request_id: object, result: object) -> Dict[str, object]:
        return {"jsonrpc": "2.0", "id": request_id, "result": result}


def read_message(stream) -> Optional[Dict[str, object]]:
    content_length = None
    while True:
        line = stream.readline()
        if not line:
            return None
        if line in (b"\r\n", b"\n"):
            break
        name, value = line.decode("ascii").split(":", 1)
        if name.lower() == "content-length":
            content_length = int(value.strip())
    if content_length is None:
        return None
    return json.loads(stream.read(content_length).decode("utf-8"))


def write_message(stream, message: Dict[str, object]) -> None:
    payload = json.dumps(message, separators=(",", ":")).encode("utf-8")
    stream.write("Content-Length: {}\r\n\r\n".format(len(payload)).encode("ascii"))
    stream.write(payload)
    stream.flush()


def serve() -> None:
    server = LanguageServer()
    while True:
        message = read_message(sys.stdin.buffer)
        if message is None:
            return
        response = server.handle(message)
        if response is not None:
            write_message(sys.stdout.buffer, response)


def debug_definition(arguments: argparse.Namespace) -> int:
    path = pathlib.Path(arguments.file).resolve()
    index = WorkspaceIndex(pathlib.Path(arguments.root).resolve())
    declaration = index.definition(
        path_to_uri(path), arguments.line - 1, arguments.character - 1
    )
    if declaration is None:
        print("null")
        return 1
    print(json.dumps(declaration.location(), sort_keys=True))
    return 0


def main(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(description="Range language server")
    subparsers = parser.add_subparsers(dest="command")
    definition = subparsers.add_parser(
        "definition", help="resolve a one-based source position"
    )
    definition.add_argument("file")
    definition.add_argument("line", type=int)
    definition.add_argument("character", type=int)
    definition.add_argument("--root", default=str(pathlib.Path.cwd()))
    arguments = parser.parse_args(argv)
    if arguments.command == "definition":
        return debug_definition(arguments)
    serve()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
