<button {{ $attributes->merge(['type' => 'submit', 'class' => 'inline-flex items-center px-4 py-2 button-bg text-genshin border border-transparent rounded-sm font-bold text-xs uppercase tracking-widest hover:bg-genshin hover:text-gold focus:outline-none disabled:opacity-25 transition ease-in-out duration-75']) }}>
    {{ $slot }}
</button>
