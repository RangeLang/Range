window.NeatCore = window.NeatCore || {
  routeLabel(path) {
    if (path === "/") {
      return "Home";
    }
    const segment = path.split("/").filter(Boolean).pop() ?? "Route";
    return segment.charAt(0).toUpperCase() + segment.slice(1);
  }
};
