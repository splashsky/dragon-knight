@props(['disabled' => false])

<input {{ $disabled ? 'disabled' : '' }} {!! $attributes->merge(['class' => 'rounded-sm shadow-sm border-gray-300 focus:border-gold focus:ring focus:ring-gold focus:ring-opacity-50']) !!}>
