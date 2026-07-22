<script lang="ts">
  import { data } from "$lib/benchmarks";
  import CodeBlock from "./CodeBlock.svelte";

  const commands = data.procedure.commands;
  const runs = Number(data.configuration.runs) || 5;
  const buildLanes = [
    ["C", "cc · O3"],
    ["C++", "c++ · O3"],
    ["Rust", "rustc · opt 3"],
    ["Go", "go build"],
    ["Swift", "swiftc · Ounchecked"],
    ["Range", "LLVM · clang O3"],
  ];
</script>

<range-procedure-graph role="img" aria-label={`Generated benchmark source fans out into optimized builds for C, C++, Rust, Go, Swift, and Range. The binaries run ${runs} times in rotating order, outputs are validated, and median wall time, CPU time, and peak memory are published.`}>
  <div class="procedureGraph">
    <div class="procedureNode procedureSource"><span class="procedureIndex">01</span><strong>Generated source</strong><small>isolated case directory</small></div>
    <div class="procedureConnector" aria-hidden="true"><span></span></div>
    <div class="procedureBuilds">
      <span class="procedureIndex">02 · optimized builds</span>
      <ul>{#each buildLanes as lane}<li><strong>{lane[0]}</strong><span>{lane[1]}</span></li>{/each}</ul>
    </div>
    <div class="procedureConnector" aria-hidden="true"><span></span></div>
    <div class="procedureNode procedureRuns"><span class="procedureIndex">03</span><strong>Rotating run order</strong><small>{runs} measured runs</small><span class="procedureSamples" aria-hidden="true">{#each Array(runs) as _, index}<i>{index + 1}</i>{/each}</span></div>
    <div class="procedureConnector" aria-hidden="true"><span></span></div>
    <div class="procedureNode procedureValidate"><span class="procedureIndex">04</span><strong>Validate output</strong><small>exit code + identical result</small></div>
    <div class="procedureConnector" aria-hidden="true"><span></span></div>
    <div class="procedureNode procedureResult"><span class="procedureIndex">05</span><strong>Median results</strong><small>wall · CPU · peak RSS</small></div>
  </div>
</range-procedure-graph>
<details class="procedureDetails">
  <summary>Commands and notes</summary>
  <div class="procedureDetailsBody">
    <div class="runCommands">
      <CodeBlock source={`${commands.suite.join("\n")}\n`} syntax="shellscript" label="Suite" />
      <CodeBlock source={`${commands.c.join("\n")}\n`} syntax="shellscript" label="C" />
      <CodeBlock source={`${commands.range.join("\n")}\n`} syntax="shellscript" label="Range" />
    </div>
    <ul class="runNotes">{#each data.procedure.notes as note}<li>{note}</li>{/each}</ul>
  </div>
</details>
