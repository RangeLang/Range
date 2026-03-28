<script lang="ts">
	type Part = {
		id: string;
		label: string;
		description: string;
	};

	type Example = {
		id: string;
		title: string;
		group: string;
		summary: string;
		lines: Array<
			Array<{
				text: string;
				partId?: string;
			}>
		>;
		parts: Part[];
	};

	const examples: Example[] = [
		{
			id: 'function',
			title: 'Function',
			group: 'Declarations',
			summary: 'A function has a name, parameters, an optional return type, and a block body.',
			lines: [
				[
					{ text: 'function', partId: 'function-keyword' },
					{ text: ' ' },
					{ text: 'greet', partId: 'function-name' },
					{ text: '(', partId: 'parameter-list' },
					{ text: 'name', partId: 'parameter-name' },
					{ text: ': ' },
					{ text: 'String', partId: 'parameter-type' },
					{ text: ')', partId: 'parameter-list' },
					{ text: ' ' },
					{ text: '->', partId: 'return-arrow' },
					{ text: ' ' },
					{ text: 'Void', partId: 'return-type' },
					{ text: ' ' },
					{ text: '{', partId: 'block' }
				],
				[{ text: '    ' }, { text: 'log(name)', partId: 'statement' }],
				[{ text: '}', partId: 'block' }]
			],
			parts: [
				{
					id: 'function-keyword',
					label: 'function',
					description: 'This starts a function declaration.'
				},
				{
					id: 'function-name',
					label: 'greet',
					description: 'This is the function name.'
				},
				{
					id: 'parameter-list',
					label: '(name: String)',
					description: 'This is the parameter list.'
				},
				{
					id: 'parameter-name',
					label: 'name',
					description: 'This is the parameter name used inside the body.'
				},
				{
					id: 'parameter-type',
					label: 'String',
					description: 'This is the parameter type.'
				},
				{
					id: 'return-arrow',
					label: '->',
					description: 'This introduces the return type.'
				},
				{
					id: 'return-type',
					label: 'Void',
					description: 'This is the return type.'
				},
				{
					id: 'block',
					label: '{ ... }',
					description: 'This is the block body. A block is an ordered sequence of statements.'
				},
				{
					id: 'statement',
					label: 'log(name)',
					description: 'This is a statement inside the block.'
				}
			]
		},
		{
			id: 'block',
			title: 'Block',
			group: 'Statements',
			summary: 'A block is just a body container for ordered statements.',
			lines: [
				[{ text: '{', partId: 'block-brace' }],
				[{ text: '    ' }, { text: 'value count = 0', partId: 'statement-one' }],
				[{ text: '    ' }, { text: 'log(count)', partId: 'statement-two' }],
				[{ text: '}', partId: 'block-brace' }]
			],
			parts: [
				{
					id: 'block-brace',
					label: '{ ... }',
					description: 'The braces are the source-level spelling of a block.'
				},
				{
					id: 'statement-one',
					label: 'value count = 0',
					description: 'A declaration can be a statement inside a block.'
				},
				{
					id: 'statement-two',
					label: 'log(count)',
					description: 'An expression statement can also appear inside a block.'
				}
			]
		},
		{
			id: 'if',
			title: 'If',
			group: 'Statements',
			summary: 'An if statement chooses between block bodies based on a condition.',
			lines: [
				[
					{ text: 'if', partId: 'if-keyword' },
					{ text: ' ' },
					{ text: 'count > 0', partId: 'condition' },
					{ text: ' ' },
					{ text: '{', partId: 'then-body' }
				],
				[{ text: '    ' }, { text: 'log(count)', partId: 'then-statement' }],
				[
					{ text: '}', partId: 'then-body' },
					{ text: ' ' },
					{ text: 'else', partId: 'else-keyword' },
					{ text: ' ' },
					{ text: '{', partId: 'else-body' }
				],
				[{ text: '    ' }, { text: 'log(0)', partId: 'else-statement' }],
				[{ text: '}', partId: 'else-body' }]
			],
			parts: [
				{ id: 'if-keyword', label: 'if', description: 'This starts the if statement.' },
				{
					id: 'condition',
					label: 'count > 0',
					description: 'This is the condition expression.'
				},
				{
					id: 'then-body',
					label: 'then body',
					description: 'This block runs when the condition is true.'
				},
				{
					id: 'then-statement',
					label: 'log(count)',
					description: 'This is a statement inside the then block.'
				},
				{
					id: 'else-keyword',
					label: 'else',
					description: 'This introduces the alternate branch.'
				},
				{
					id: 'else-body',
					label: 'else body',
					description: 'This block runs when the condition is false.'
				},
				{
					id: 'else-statement',
					label: 'log(0)',
					description: 'This is a statement inside the else block.'
				}
			]
		},
		{
			id: 'while',
			title: 'While',
			group: 'Statements',
			summary: 'A while statement repeats a block while its condition stays true.',
			lines: [
				[
					{ text: 'while', partId: 'while-keyword' },
					{ text: ' ' },
					{ text: 'count > 0', partId: 'condition' },
					{ text: ' ' },
					{ text: '{', partId: 'body' }
				],
				[{ text: '    ' }, { text: 'count -= 1', partId: 'statement' }],
				[{ text: '}', partId: 'body' }]
			],
			parts: [
				{ id: 'while-keyword', label: 'while', description: 'This starts the while statement.' },
				{
					id: 'condition',
					label: 'count > 0',
					description: 'This is the loop condition.'
				},
				{ id: 'body', label: '{ ... }', description: 'This is the loop body block.' },
				{
					id: 'statement',
					label: 'count -= 1',
					description: 'This is a statement inside the loop body.'
				}
			]
		},
		{
			id: 'for',
			title: 'For',
			group: 'Statements',
			summary: 'A for statement binds a pattern and iterates over a sequence.',
			lines: [
				[
					{ text: 'for', partId: 'for-keyword' },
					{ text: ' ' },
					{ text: 'item', partId: 'pattern' },
					{ text: ' ' },
					{ text: 'in', partId: 'in-keyword' },
					{ text: ' ' },
					{ text: 'items', partId: 'sequence' },
					{ text: ' ' },
					{ text: '{', partId: 'body' }
				],
				[{ text: '    ' }, { text: 'log(item)', partId: 'statement' }],
				[{ text: '}', partId: 'body' }]
			],
			parts: [
				{ id: 'for-keyword', label: 'for', description: 'This starts the for statement.' },
				{
					id: 'pattern',
					label: 'item',
					description: 'This is the pattern or binding introduced by the loop.'
				},
				{
					id: 'in-keyword',
					label: 'in',
					description: 'This separates the pattern from the sequence.'
				},
				{
					id: 'sequence',
					label: 'items',
					description: 'This is the sequence being iterated.'
				},
				{ id: 'body', label: '{ ... }', description: 'This is the loop body block.' },
				{
					id: 'statement',
					label: 'log(item)',
					description: 'This is a statement inside the loop body.'
				}
			]
		},
		{
			id: 'return',
			title: 'Return',
			group: 'Statements',
			summary: 'A return statement exits the current callable body with a value.',
			lines: [
				[
					{ text: 'return', partId: 'return-keyword' },
					{ text: ' ' },
					{ text: 'name', partId: 'expression' }
				]
			],
			parts: [
				{
					id: 'return-keyword',
					label: 'return',
					description: 'This starts the return statement.'
				},
				{
					id: 'expression',
					label: 'name',
					description: 'This is the returned expression.'
				}
			]
		},
		{
			id: 'switch',
			title: 'Switch',
			group: 'Statements',
			summary: 'A switch statement selects among case bodies based on one expression.',
			lines: [
				[
					{ text: 'switch', partId: 'switch-keyword' },
					{ text: ' ' },
					{ text: 'state', partId: 'expression' },
					{ text: ' ' },
					{ text: '{', partId: 'body' }
				],
				[
					{ text: '    ' },
					{ text: 'case', partId: 'case-keyword' },
					{ text: ' ' },
					{ text: '.ready', partId: 'case-pattern' }
				],
				[{ text: '        ' }, { text: 'log("ready")', partId: 'case-statement' }],
				[{ text: '}', partId: 'body' }]
			],
			parts: [
				{
					id: 'switch-keyword',
					label: 'switch',
					description: 'This starts the switch statement.'
				},
				{
					id: 'expression',
					label: 'state',
					description: 'This is the expression being matched.'
				},
				{ id: 'body', label: '{ ... }', description: 'This is the switch body.' },
				{
					id: 'case-keyword',
					label: 'case',
					description: 'This starts a case inside the switch.'
				},
				{
					id: 'case-pattern',
					label: '.ready',
					description: 'This is the case pattern.'
				},
				{
					id: 'case-statement',
					label: 'log("ready")',
					description: 'This is a statement inside the case body.'
				}
			]
		},
		{
			id: 'switch-case',
			title: 'SwitchCase',
			group: 'Statements',
			summary: 'A switch case has a pattern and a block body.',
			lines: [
				[
					{ text: 'case', partId: 'case-keyword' },
					{ text: ' ' },
					{ text: '.ready', partId: 'pattern' }
				],
				[{ text: '    ' }, { text: 'log("ready")', partId: 'body' }]
			],
			parts: [
				{
					id: 'case-keyword',
					label: 'case',
					description: 'This starts the case.'
				},
				{
					id: 'pattern',
					label: '.ready',
					description: 'This is the case pattern expression.'
				},
				{
					id: 'body',
					label: 'log("ready")',
					description: 'This is the body content of the case.'
				}
			]
		},
		{
			id: 'parameter',
			title: 'Parameter',
			group: 'Declarations',
			summary: 'A parameter gives a function body a named typed input.',
			lines: [
				[
					{ text: 'function ' },
					{ text: 'greet', partId: 'host-function' },
					{ text: '(' },
					{ text: 'name', partId: 'parameter-name' },
					{ text: ': ' },
					{ text: 'String', partId: 'parameter-type' },
					{ text: ')' }
				]
			],
			parts: [
				{
					id: 'host-function',
					label: 'greet',
					description: 'This is the function that owns the parameter.'
				},
				{
					id: 'parameter-name',
					label: 'name',
					description: 'This is the local parameter name.'
				},
				{
					id: 'parameter-type',
					label: 'String',
					description: 'This is the parameter type.'
				}
			]
		}
	];

	const navigation = [
		{
			title: 'Declarations',
			items: examples.filter((example) => example.group === 'Declarations')
		},
		{
			title: 'Statements',
			items: examples.filter((example) => example.group === 'Statements')
		}
	];

	let selected = $state<Example>(examples[0]);
	let active = $state<Part>(examples[0].parts[0]);

	function selectExample(id: string) {
		const match = examples.find((example) => example.id === id);
		if (!match) return;
		selected = match;
		active = match.parts[0];
	}

	function setActive(id: string | undefined) {
		if (!id) return;
		const match = selected.parts.find((part) => part.id === id);
		if (match) active = match;
	}
</script>

<svelte:head>
	<title>NeatStudio</title>
</svelte:head>

<div class="page">
	<aside class="sidebar">
		<div class="sidebar-title">Syntax</div>
		<nav class="sidebar-nav" aria-label="Syntax examples">
			{#each navigation as section}
				<div class="sidebar-section">
					<div class="sidebar-section-title">{section.title}</div>
					<div class="sidebar-section-items">
						{#each section.items as example}
							<button
								class:selected={example.id === selected.id}
								class="sidebar-item"
								type="button"
								onclick={() => selectExample(example.id)}
							>
								{example.title}
							</button>
						{/each}
					</div>
				</div>
			{/each}
		</nav>
	</aside>

	<main class="main">
		<div class="viewer">
			<div class="code-panel">
				<div class="example-title">{selected.title}</div>
				<div class="example-summary">{selected.summary}</div>

				<pre class="code"><code
						>{#each selected.lines as line, lineIndex}{#each line as token}<button
									class="token"
									class:interactive={Boolean(token.partId)}
									type="button"
									disabled={!token.partId}
									onmouseenter={() => setActive(token.partId)}
									onfocus={() => setActive(token.partId)}>{token.text}</button
								>{/each}{#if lineIndex < selected.lines.length - 1}{'\n'}{/if}{/each}</code
					></pre>
			</div>

			<div class="popover" role="status" aria-live="polite">
				<div class="popover-label">{active.label}</div>
				<div class="popover-text">{active.description}</div>
			</div>
		</div>
	</main>
</div>
