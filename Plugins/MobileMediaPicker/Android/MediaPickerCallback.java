package com.binouze;

public interface MediaPickerCallback
{
    public void onUrlPicked(String url);
    public void onMultipleUrlsPicked(String[] urls);
}
